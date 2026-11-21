const OFFSET_H = 3;
const PERIODS = ['daily', 'weekly', 'monthly'] as const;

type ContribPeriod = typeof PERIODS[number];

const ksa = () => new Date(Date.now() + OFFSET_H * 3600 * 1000);

// يوم: YYYY-MM-DD | أسبوع: تاريخ يوم الإثنين | شهر: YYYY-MM
export function periodKey(period: ContribPeriod): string {
  const date = ksa();
  if (period === 'monthly') return date.toISOString().slice(0, 7);
  if (period === 'weekly') {
    const day = (date.getUTCDay() + 6) % 7;
    return new Date(date.getTime() - day * 86400000).toISOString().slice(0, 10);
  }
  return date.toISOString().slice(0, 10);
}

/**
 * Returns contribution statements to append to the successful gift transaction
 * batch. The transaction is already marked succeeded before these statements run,
 * so failed or uncommitted gifts can never enter the ranking.
 */
export function addRoomContribution(
  db: D1Database,
  giftTransactionId: string
): D1PreparedStatement[] {
  return PERIODS.map((period) => {
    const sql =
      'INSERT INTO room_contrib(room_id,user_id,period,pkey,amount) ' +
      'SELECT room_id,sender_user_id,?,?,coin_cost FROM gift_transactions ' +
      "WHERE id=? AND status='succeeded' " +
      'ON CONFLICT(room_id,user_id,period,pkey) ' +
      'DO UPDATE SET amount = room_contrib.amount + excluded.amount';
    return db.prepare(sql).bind(period, periodKey(period), giftTransactionId);
  });
}

type JsonResponder = (data: unknown, status?: number) => Response;

export async function handleRoomContrib(
  request: Request,
  db: D1Database,
  authenticatedUserId: string,
  respond: JsonResponder
): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== '/api/room/contributors') return null;
  if (request.method !== 'GET') return respond({ ok: false, error: 'method' }, 405);

  try {
    const roomId = (url.searchParams.get('room_id') ?? '').trim();
    const period = (url.searchParams.get('period') ?? 'daily') as ContribPeriod;
    if (!roomId || roomId.length > 80 || !PERIODS.includes(period)) {
      return respond({ ok: false, error: 'bad params' }, 400);
    }

    const key = periodKey(period);
    const top = await db.prepare(
      'SELECT c.user_id, c.amount, COALESCE(p.display_name, \'\') AS name, ' +
      'COALESCE(p.avatar_key, \'\') AS avatar ' +
      'FROM room_contrib c LEFT JOIN profiles p ON p.user_id = c.user_id ' +
      'WHERE c.room_id=? AND c.period=? AND c.pkey=? ' +
      'ORDER BY c.amount DESC, c.user_id ASC LIMIT 30'
    ).bind(roomId, period, key).all<Record<string, unknown>>();

    const mine = await db.prepare(
      'SELECT COALESCE(p.display_name, \'\') AS name, COALESCE(p.avatar_key, \'\') AS avatar, ' +
      'COALESCE(c.amount, 0) AS amount ' +
      'FROM profiles p LEFT JOIN room_contrib c ON c.user_id=p.user_id ' +
      'AND c.room_id=? AND c.period=? AND c.pkey=? WHERE p.user_id=? LIMIT 1'
    ).bind(roomId, period, key, authenticatedUserId)
      .first<{ name: string; avatar: string; amount: number }>();

    let rank: number | null = null;
    const amount = Number(mine?.amount ?? 0);
    if (amount > 0) {
      const ranked = await db.prepare(
        'SELECT COUNT(*) AS n FROM room_contrib ' +
        'WHERE room_id=? AND period=? AND pkey=? AND amount>?'
      ).bind(roomId, period, key, amount).first<{ n: number }>();
      rank = Number(ranked?.n ?? 0) + 1;
    }

    return respond({
      ok: true,
      period,
      entries: (top.results ?? []).map((row) => ({
        user_id: row.user_id,
        name: row.name ?? '',
        avatar: row.avatar ?? '',
        amount: Number(row.amount ?? 0),
      })),
      me: {
        user_id: authenticatedUserId,
        name: mine?.name ?? '',
        avatar: mine?.avatar ?? '',
        amount,
        rank,
      },
    });
  } catch (error) {
    console.error('[room.contributors] failed', error instanceof Error ? error.message : 'UnknownError');
    return respond({ ok: false, error: 'contributors_unavailable' }, 500);
  }
}
