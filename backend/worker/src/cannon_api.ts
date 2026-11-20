type CannonUser = { id: string };
type CannonAdmin = { id: string; role: string };
type CannonEnv = { DB?: D1Database };
type CannonJson = (data: unknown, status?: number, origin?: string, env?: any) => Response;
type CannonAuthUser = (request: Request, db: D1Database) => Promise<CannonUser | null>;
type CannonAuthAdmin = (request: Request, db: D1Database) => Promise<CannonAdmin | null>;
type CannonLevelConfig = { level: number; title?: string; need: number; prizes: CannonPrizeConfig[] };
type CannonPrizeConfig = { key: string; name: string; type: string; value: string; icon: string; top1: boolean; weight?: number; rare?: boolean };

const DEFAULT_LEVELS: CannonLevelConfig[] = [
  { level: 1, need: 90000, prizes: [
    { key: "frame_l1", name: "إطار المستوى الأول", type: "frame", value: "frame_l1", icon: "", top1: true, weight: 0 },
    { key: "bubble_l1", name: "فقاعة نادرة", type: "bubble", value: "bubble_l1", icon: "", top1: false, weight: 10, rare: true },
    { key: "coins_l1", name: "500 عملة", type: "coins", value: "500", icon: "", top1: false, weight: 60 },
    { key: "gift_l1_a", name: "هدية مميزة", type: "gift", value: "gift_l1_a", icon: "", top1: false, weight: 20 },
    { key: "gift_l1_b", name: "هدية إضافية", type: "gift", value: "gift_l1_b", icon: "", top1: false, weight: 20 }
  ]},
  { level: 2, need: 900000, prizes: [
    { key: "entry_l2", name: "دخول مميز", type: "entry", value: "entry_l2", icon: "", top1: true, weight: 0 },
    { key: "frame_l2", name: "إطار نادر", type: "frame", value: "frame_l2", icon: "", top1: false, weight: 10, rare: true },
    { key: "coins_l2", name: "5,000 عملة", type: "coins", value: "5000", icon: "", top1: false, weight: 60 },
    { key: "gift_l2", name: "هدية المستوى الثاني", type: "gift", value: "gift_l2", icon: "", top1: false, weight: 20 },
    { key: "badge_l2", name: "شارة المستوى الثاني", type: "badge", value: "badge_l2", icon: "", top1: false, weight: 15 }
  ]},
  { level: 3, need: 5000000, prizes: [
    { key: "entry_l3", name: "دخول فاخر", type: "entry", value: "entry_l3", icon: "", top1: true, weight: 0 },
    { key: "frame_l3", name: "إطار أزرق", type: "frame", value: "frame_l3", icon: "", top1: false, weight: 10, rare: true },
    { key: "coins_l3", name: "25,000 عملة", type: "coins", value: "25000", icon: "", top1: false, weight: 60 },
    { key: "gift_l3", name: "هدية المستوى الثالث", type: "gift", value: "gift_l3", icon: "", top1: false, weight: 20 },
    { key: "badge_l3", name: "شارة المستوى الثالث", type: "badge", value: "badge_l3", icon: "", top1: false, weight: 15 }
  ]},
  { level: 4, need: 14000000, prizes: [
    { key: "entry_l4", name: "دخول ملكي", type: "entry", value: "entry_l4", icon: "", top1: true, weight: 0 },
    { key: "coins_l4", name: "100,000 عملة", type: "coins", value: "100000", icon: "", top1: false, weight: 60 },
    { key: "badge_l4", name: "شارة المستوى الرابع", type: "badge", value: "badge_l4", icon: "", top1: false, weight: 15 },
    { key: "wave_l4", name: "موجة ملكية", type: "wave", value: "wave_l4", icon: "", top1: false, weight: 15 }
  ]}
];

function saudiDay(): string {
  return new Date(Date.now() + 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
function nowSeconds(): number { return Math.floor(Date.now() / 1000); }
function parseLevels(value: string | null | undefined): CannonLevelConfig[] {
  if (!value) return DEFAULT_LEVELS;
  try {
    const parsed = JSON.parse(value);
    if (Array.isArray(parsed) && parsed.length) return parsed as CannonLevelConfig[];
  } catch {}
  return DEFAULT_LEVELS;
}
async function cannonSettings(db: D1Database) {
  const row = await db.prepare(
    "SELECT enabled, banner_enabled AS bannerEnabled, banner_image_url AS bannerImageUrl, frame_image_url AS frameImageUrl, levels_json AS levelsJson FROM cannon_settings WHERE id='current'"
  ).first<{ enabled: number; bannerEnabled: number; bannerImageUrl: string; frameImageUrl: string; levelsJson: string }>();
  return {
    enabled: row?.enabled === 1,
    bannerEnabled: row?.bannerEnabled === 1,
    bannerImageUrl: row?.bannerImageUrl ?? "",
    frameImageUrl: row?.frameImageUrl ?? "",
    levels: parseLevels(row?.levelsJson)
  };
}
function prizeFor(prizes: CannonPrizeConfig[], share: number): CannonPrizeConfig | null {
  const pool = prizes.filter(p => !p.top1 && Number(p.weight ?? 0) > 0);
  if (!pool.length) return prizes.find(p => !p.top1) ?? prizes[0] ?? null;
  const weighted = pool.map(p => ({ prize: p, weight: Math.max(1, Number(p.weight ?? 1)) * (p.rare ? 1 + Math.max(0, share) * 20 : 1) }));
  const total = weighted.reduce((sum, item) => sum + item.weight, 0);
  let point = Math.random() * total;
  for (const item of weighted) { point -= item.weight; if (point <= 0) return item.prize; }
  return weighted[weighted.length - 1].prize;
}
async function ensureCannonRoom(db: D1Database, roomId: string, day: string) {
  await db.prepare(
    "INSERT OR IGNORE INTO cannon_rooms (room_id, day, level, progress, launching_until, updated_at) SELECT id, ?, 1, 0, 0, ? FROM rooms WHERE id=?"
  ).bind(day, new Date().toISOString(), roomId).run();
}
async function tryLaunches(db: D1Database, roomId: string, day: string, levels: CannonLevelConfig[]) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const room = await db.prepare(
      "SELECT level, progress FROM cannon_rooms WHERE room_id=? AND day=? LIMIT 1"
    ).bind(roomId, day).first<{ level: number; progress: number }>();
    if (!room) return;
    const cfg = levels.find(level => level.level === room.level);
    if (!cfg || room.progress < cfg.need) return;

    const presence = await db.prepare(
      "SELECT p.user_id AS userId, COALESCE(c.amount,0) AS contribution FROM cannon_presence p " +
      "LEFT JOIN cannon_contrib c ON c.room_id=p.room_id AND c.day=? AND c.user_id=p.user_id AND c.level=? " +
      "WHERE p.room_id=? AND p.seen_at>=? ORDER BY contribution DESC, p.seen_at DESC LIMIT 200"
    ).bind(day, room.level, roomId, nowSeconds() - 90).all<{ userId: string; contribution: number }>();
    const eligible = presence.results ?? [];
    const top = eligible.reduce<{userId:string;contribution:number}|null>((best, item) => !best || item.contribution > best.contribution ? item : best, null);
    const topPrize = cfg.prizes.find(p => p.top1);
    const launchId = crypto.randomUUID();
    const now = nowSeconds();
    const nextLevel = room.level < Math.max(...levels.map(x => x.level)) ? room.level + 1 : room.level;
    const statements: D1PreparedStatement[] = [
      db.prepare(
        "UPDATE cannon_rooms SET progress=progress-?, level=?, launching_until=?, last_launch_id=?, updated_at=? " +
        "WHERE room_id=? AND day=? AND level=? AND progress>=?"
      ).bind(cfg.need, nextLevel, now + 20, launchId, new Date().toISOString(), roomId, day, room.level, cfg.need),
      db.prepare(
        "INSERT INTO cannon_launches (id, room_id, level, day, created_at) " +
        "SELECT ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM cannon_rooms WHERE room_id=? AND day=? AND last_launch_id=?)"
      ).bind(launchId, roomId, room.level, day, now, roomId, day, launchId),
      db.prepare(
        "INSERT INTO cannon_launch_contributors (launch_id, room_id, user_id, contribution) " +
        "SELECT ?, ?, user_id, amount FROM cannon_contrib " +
        "WHERE room_id=? AND day=? AND level=? AND amount>0 " +
        "AND EXISTS (SELECT 1 FROM cannon_launches WHERE id=?)"
      ).bind(launchId, roomId, roomId, day, room.level, launchId),
      db.prepare(
        "UPDATE cannon_contrib SET amount=0 WHERE room_id=? AND day=? AND level=? " +
        "AND EXISTS (SELECT 1 FROM cannon_launches WHERE id=?)"
      ).bind(roomId, day, room.level, launchId)
    ];
    if (top && topPrize) {
      statements.push(db.prepare(
        "INSERT INTO cannon_claims (id, launch_id, room_id, user_id, reward_key, reward_type, reward_value, reward_name, created_at) " +
        "SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM cannon_launches WHERE id=?)"
      ).bind(crypto.randomUUID(), launchId, roomId, top.userId, topPrize.key, topPrize.type, topPrize.value, topPrize.name, new Date().toISOString(), launchId));
    }
    for (const item of eligible) {
      if (top && item.userId === top.userId) continue;
      const share = room.progress > 0 ? item.contribution / room.progress : 0;
      const prize = prizeFor(cfg.prizes, share);
      if (!prize) continue;
      statements.push(db.prepare(
        "INSERT INTO cannon_claims (id, launch_id, room_id, user_id, reward_key, reward_type, reward_value, reward_name, created_at) " +
        "SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM cannon_launches WHERE id=?)"
      ).bind(crypto.randomUUID(), launchId, roomId, item.userId, prize.key, prize.type, prize.value, prize.name, new Date().toISOString(), launchId));
    }
    const result = await db.batch(statements);
    if ((result[0]?.meta?.changes ?? 0) !== 1) continue;
  }
}

export async function addCannonEnergy(
  db: D1Database,
  transactionId: string,
  roomId: string,
  senderUserId: string,
  coinCost: number
): Promise<void> {
  if (!Number.isSafeInteger(coinCost) || coinCost <= 0) return;
  const settings = await cannonSettings(db);
  if (!settings.enabled) return;
  const day = saudiDay();
  await ensureCannonRoom(db, roomId, day);
  const now = new Date().toISOString();
  const results = await db.batch([
    db.prepare(
      "INSERT OR IGNORE INTO cannon_energy_transactions (transaction_id, room_id, user_id, coin_cost, created_at) " +
      "SELECT ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM gift_transactions WHERE id=? AND status='succeeded' AND room_id=? AND sender_user_id=? AND coin_cost=?)"
    ).bind(transactionId, roomId, senderUserId, coinCost, now, transactionId, roomId, senderUserId, coinCost),
    db.prepare(
      "INSERT INTO cannon_contrib (room_id, day, user_id, level, amount) " +
      "SELECT room_id, day, ?, level, ? FROM cannon_rooms WHERE room_id=? AND day=? " +
      "AND EXISTS (SELECT 1 FROM cannon_energy_transactions WHERE transaction_id=? AND applied_at IS NULL) " +
      "ON CONFLICT(room_id,day,user_id,level) DO UPDATE SET amount=cannon_contrib.amount+excluded.amount"
    ).bind(senderUserId, coinCost, roomId, day, transactionId),
    db.prepare(
      "UPDATE cannon_rooms SET progress=progress+?, updated_at=? WHERE room_id=? AND day=? " +
      "AND EXISTS (SELECT 1 FROM cannon_energy_transactions WHERE transaction_id=? AND applied_at IS NULL)"
    ).bind(coinCost, now, roomId, day, transactionId),
    db.prepare("UPDATE cannon_energy_transactions SET applied_at=? WHERE transaction_id=? AND applied_at IS NULL")
      .bind(now, transactionId)
  ]);
  if ((results[0]?.meta?.changes ?? 0) !== 1) return;
  await tryLaunches(db, roomId, day, settings.levels);
}

export async function handleCannonRequest(
  request: Request,
  env: CannonEnv,
  origin: string | undefined,
  authenticateUser: CannonAuthUser,
  authenticateAdmin: CannonAuthAdmin,
  hasAdminPermission: (actor: CannonAdmin, permission: "rooms.read" | "rooms.manage") => boolean,
  json: CannonJson
): Promise<Response | null> {
  const url = new URL(request.url);
  const db = env.DB;
  const isAdminRoute = url.pathname === "/api/v1/admin/cannon/settings";
  const isCannonRoute = url.pathname === "/api/cannon/state" || url.pathname === "/api/cannon/banners" || url.pathname === "/api/cannon/claim" || url.pathname === "/api/cannon/contributors" || url.pathname === "/api/cannon/winners";
  if (!isAdminRoute && !isCannonRoute) return null;
  if (!db) return json({ error: "database_unavailable" }, 503, origin, env);

  try {
    if (isAdminRoute) {
      const actor = await authenticateAdmin(request, db);
      if (!actor) return json({ error: "authentication_required" }, 401, origin, env);
      if (request.method === "GET") {
        if (!hasAdminPermission(actor, "rooms.read")) return json({ error: "permission_denied" }, 403, origin, env);
        const row = await db.prepare(
          "SELECT enabled, banner_enabled AS bannerEnabled, banner_image_url AS bannerImageUrl, frame_image_url AS frameImageUrl, levels_json AS levelsJson, updated_at AS updatedAt FROM cannon_settings WHERE id='current'"
        ).first<Record<string, unknown>>();
        return json({ ok: true, settings: { enabled: Number(row?.enabled ?? 1) === 1, bannerEnabled: Number(row?.bannerEnabled ?? 1) === 1, bannerImageUrl: row?.bannerImageUrl ?? "", frameImageUrl: row?.frameImageUrl ?? "", levels: parseLevels(String(row?.levelsJson ?? "")), updatedAt: row?.updatedAt ?? null } }, 200, origin, env);
      }
      if (request.method === "PATCH") {
        if (!hasAdminPermission(actor, "rooms.manage")) return json({ error: "permission_denied" }, 403, origin, env);
        let body: Record<string, unknown>;
        try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
        const enabled = body.enabled === undefined ? undefined : body.enabled === true;
        const bannerEnabled = body.bannerEnabled === undefined ? undefined : body.bannerEnabled === true;
        const bannerImageUrl = body.bannerImageUrl === undefined ? undefined : String(body.bannerImageUrl ?? "").trim();
        const frameImageUrl = body.frameImageUrl === undefined ? undefined : String(body.frameImageUrl ?? "").trim();
        const levels = body.levels === undefined ? undefined : body.levels;
        if ((bannerImageUrl !== undefined && bannerImageUrl.length > 2048) || (frameImageUrl !== undefined && frameImageUrl.length > 2048) ||
            (bannerImageUrl && !/^https:\/\//i.test(bannerImageUrl)) || (frameImageUrl && !/^https:\/\//i.test(frameImageUrl))) {
          return json({ error: "invalid_cannon_asset_url" }, 400, origin, env);
        }
        let levelsJson: string | undefined;
        if (levels !== undefined) {
          if (!Array.isArray(levels) || levels.length < 1 || levels.length > 150) return json({ error: "invalid_cannon_levels" }, 400, origin, env);
          const levelIds = new Set<number>();
          for (const level of levels as any[]) {
            const levelId = Number(level?.level);
            if (!Number.isSafeInteger(levelId) || levelId !== levelIds.size + 1 || levelId < 1 || levelId > 150 || levelIds.has(levelId) ||
                (level?.title !== undefined && (typeof level.title !== "string" || level.title.trim().length > 60)) ||
                !Number.isSafeInteger(Number(level?.need)) || Number(level.need) < 1 || Number(level.need) > 1000000000000 ||
                !Array.isArray(level?.prizes) || level.prizes.length < 1 || level.prizes.length > 40) {
              return json({ error: "invalid_cannon_levels" }, 400, origin, env);
            }
            levelIds.add(levelId);
            const prizeKeys = new Set<string>();
            let top1Count = 0;
            for (const prize of level.prizes) {
              const weight = prize?.weight === undefined ? 0 : Number(prize.weight);
              if (!prize || typeof prize.key !== "string" || !/^[a-z0-9_-]{1,80}$/i.test(prize.key) || prizeKeys.has(prize.key) ||
                  typeof prize.name !== "string" || prize.name.trim().length < 1 || prize.name.length > 100 ||
                  typeof prize.type !== "string" || typeof prize.value !== "string" || prize.value.length > 120 ||
                  typeof prize.icon !== "string" || prize.icon.length > 2048 ||
                  (prize.icon && !/^https:\/\//i.test(prize.icon)) ||
                  !["coins","frame","bubble","entry","gift","badge","wave","item"].includes(prize.type) ||
                  !Number.isFinite(weight) || weight < 0 || weight > 100000 ||
                  typeof prize.top1 !== "boolean" || (prize.rare !== undefined && typeof prize.rare !== "boolean") ||
                  (prize.type === "coins" && (!/^\d+$/.test(prize.value) || Number(prize.value) < 1 || Number(prize.value) > 1000000000))) {
                return json({ error: "invalid_cannon_prize" }, 400, origin, env);
              }
              prizeKeys.add(prize.key);
              if (prize.top1) top1Count++;
            }
            if (top1Count > 1) return json({ error: "multiple_top1_prizes" }, 400, origin, env);
          }
          if (levelIds.size !== levels.length) return json({ error: "invalid_cannon_levels" }, 400, origin, env);
          levelsJson = JSON.stringify(levels);
        }
        const current = await db.prepare(
          "SELECT enabled, banner_enabled, banner_image_url, frame_image_url, levels_json FROM cannon_settings WHERE id='current'"
        ).first<Record<string, unknown>>();
        if (!current) return json({ error: "cannon_settings_missing" }, 503, origin, env);
        const now = new Date().toISOString();
        await db.prepare(
          "UPDATE cannon_settings SET enabled=?, banner_enabled=?, banner_image_url=?, frame_image_url=?, levels_json=?, updated_by_admin_id=?, updated_at=? WHERE id='current'"
        ).bind(enabled === undefined ? Number(current.enabled) : (enabled ? 1 : 0),
          bannerEnabled === undefined ? Number(current.banner_enabled) : (bannerEnabled ? 1 : 0),
          bannerImageUrl === undefined ? String(current.banner_image_url ?? "") : bannerImageUrl,
          frameImageUrl === undefined ? String(current.frame_image_url ?? "") : frameImageUrl,
          levelsJson === undefined ? String(current.levels_json) : levelsJson, actor.id, now).run();
        return json({ ok: true, updatedAt: now }, 200, origin, env);
      }
      return json({ error: "method_not_allowed" }, 405, origin, env);
    }

    const user = await authenticateUser(request, db);
    if (!user) return json({ error: "authentication_required" }, 401, origin, env);
    const settings = await cannonSettings(db);

    if (url.pathname === "/api/cannon/state" && request.method === "GET") {
      if (!settings.enabled) return json({ ok: true, disabled: true }, 200, origin, env);
      const roomId = (url.searchParams.get("room_id") ?? "").trim();
      if (!/^[0-9a-f-]{36}$/i.test(roomId)) return json({ error: "invalid_room_id" }, 400, origin, env);
      const room = await db.prepare(
        "SELECT r.id AS room_id, r.name AS title, COALESCE(p.avatar_key,'') AS avatar " +
        "FROM rooms r LEFT JOIN profiles p ON p.user_id=r.owner_user_id WHERE r.id=? AND r.status='active' LIMIT 1"
      ).bind(roomId).first<{ room_id: string; title: string; avatar: string }>();
      if (!room) return json({ error: "room_not_found" }, 404, origin, env);
      const activeVisit = await db.prepare(
        "SELECT id FROM room_chat_visits WHERE room_id=? AND user_id=? AND exited_at IS NULL AND last_seen_at>=? LIMIT 1"
      ).bind(roomId, user.id, new Date(Date.now() - 45000).toISOString()).first<{ id: string }>();
      if (!activeVisit) return json({ error: "room_membership_required" }, 403, origin, env);
      const day = saudiDay();
      await ensureCannonRoom(db, roomId, day);
      await db.prepare(
        "INSERT INTO cannon_presence (room_id,user_id,seen_at) VALUES (?,?,?) " +
        "ON CONFLICT(room_id,user_id) DO UPDATE SET seen_at=excluded.seen_at"
      ).bind(roomId, user.id, nowSeconds()).run();
      const state = await db.prepare(
        "SELECT level, progress, launching_until AS launchingUntil, last_launch_id AS launchId FROM cannon_rooms WHERE room_id=? AND day=? LIMIT 1"
      ).bind(roomId, day).first<{ level: number; progress: number; launchingUntil: number; launchId: string | null }>();
      const currentLevel = settings.levels.find(x => x.level === Number(state?.level ?? 1));
      const need = currentLevel?.need ?? 0;
      const [mine, pending, contributors] = await Promise.all([
        db.prepare("SELECT amount FROM cannon_contrib WHERE room_id=? AND day=? AND user_id=? AND level=? LIMIT 1")
          .bind(roomId, day, user.id, state?.level ?? 1).first<{ amount: number }>(),
        db.prepare(
          "SELECT id, reward_type, reward_value, reward_name FROM cannon_claims WHERE room_id=? AND user_id=? AND claimed=0 ORDER BY created_at ASC LIMIT 50"
        ).bind(roomId, user.id).all(),
        state?.launchId ? db.prepare(
          "SELECT user_id, user_name, avatar_url, public_id, contribution FROM (" +
          "SELECT c.user_id AS user_id, COALESCE(NULLIF(p.display_name,''), NULLIF(p.happy_id,''), 'مساهم') AS user_name, " +
          "COALESCE(p.avatar_key,'') AS avatar_url, COALESCE(p.happy_id,'') AS public_id, c.contribution AS contribution " +
          "FROM cannon_launch_contributors c LEFT JOIN profiles p ON p.user_id=c.user_id " +
          "WHERE c.launch_id=? AND c.room_id=? AND c.contribution>0 " +
          "UNION ALL " +
          "SELECT c.user_id AS user_id, COALESCE(NULLIF(p.display_name,''), NULLIF(p.happy_id,''), 'مساهم') AS user_name, " +
          "COALESCE(p.avatar_key,'') AS avatar_url, COALESCE(p.happy_id,'') AS public_id, c.amount AS contribution " +
          "FROM cannon_launches l INNER JOIN cannon_contrib c ON c.room_id=l.room_id AND c.day=l.day AND c.level=l.level " +
          "LEFT JOIN profiles p ON p.user_id=c.user_id " +
          "WHERE l.id=? AND l.room_id=? AND c.amount>0 " +
          "AND NOT EXISTS (SELECT 1 FROM cannon_launch_contributors frozen WHERE frozen.launch_id=l.id AND frozen.contribution>0)" +
          ") ORDER BY contribution DESC, user_id ASC LIMIT 200"
        ).bind(state.launchId, roomId, state.launchId, roomId).all<Record<string, unknown>>() : Promise.resolve({ results: [] as Record<string, unknown>[] })
      ]);
      return json({
        ok: true,
        room: { room_id: room.room_id, title: room.title, avatar: room.avatar, launch_id: state?.launchId ?? "", level: state?.level ?? 1, progress: state?.progress ?? 0, need, launching: Number(state?.launchingUntil ?? 0) > nowSeconds() },
        my: { contribution: mine?.amount ?? 0, pending: pending.results ?? [] },
        contributors: contributors.results ?? [],
        levels: settings.levels
      }, 200, origin, env);
    }

    if (url.pathname === "/api/cannon/winners" && request.method === "GET") {
      if (!settings.enabled) return json({ ok: true, winners: [] }, 200, origin, env);
      const roomId = (url.searchParams.get("room_id") ?? "").trim();
      const level = Number(url.searchParams.get("level") ?? 0);
      if (!/^[0-9a-f-]{36}$/i.test(roomId) ||
          !Number.isSafeInteger(level) || level < 1 || level > 150) {
        return json({ error: "invalid_winner_request" }, 400, origin, env);
      }
      const activeVisit = await db.prepare(
        "SELECT id FROM room_chat_visits WHERE room_id=? AND user_id=? AND exited_at IS NULL AND last_seen_at>=? LIMIT 1"
      ).bind(roomId, user.id, new Date(Date.now() - 45000).toISOString()).first<{ id: string }>();
      if (!activeVisit) return json({ error: "room_membership_required" }, 403, origin, env);
      const rows = await db.prepare(
        "SELECT c.user_id AS user_id, COALESCE(NULLIF(p.display_name,''), NULLIF(p.happy_id,''), 'فائز') AS user_name, " +
        "COALESCE(p.avatar_key,'') AS avatar_url, c.reward_type AS reward_type, " +
        "c.reward_value AS reward_value, c.reward_name AS reward_name, c.claimed_at AS claimed_at, " +
        "c.reward_key AS reward_key " +
        "FROM cannon_claims c LEFT JOIN profiles p ON p.user_id=c.user_id " +
        "INNER JOIN cannon_launches l ON l.id=c.launch_id " +
        "WHERE c.room_id=? AND l.level=? AND l.day=? AND c.claimed=1 " +
        "ORDER BY c.claimed_at DESC, c.created_at DESC LIMIT 100"
      ).bind(roomId, level, saudiDay()).all<Record<string, unknown>>();
      const prizeIcons = new Map<string, string>();
      for (const cfg of settings.levels) {
        if (cfg.level !== level) continue;
        for (const prize of cfg.prizes) prizeIcons.set(prize.key, prize.icon ?? "");
      }
      const winners = (rows.results ?? []).map(row => ({
        user_id: row.user_id, user_name: row.user_name, avatar_url: row.avatar_url,
        reward_type: row.reward_type, reward_value: row.reward_value,
        reward_name: row.reward_name, claimed_at: row.claimed_at,
        prize_icon: prizeIcons.get(String(row.reward_key ?? "")) ?? ""
      }));
      return json({ ok: true, level, winners }, 200, origin, env);
    }

    if (url.pathname === "/api/cannon/contributors" && request.method === "GET") {
      if (!settings.enabled) return json({ ok: true, contributors: [] }, 200, origin, env);
      const roomId = (url.searchParams.get("room_id") ?? "").trim();
      let launchId = (url.searchParams.get("launch_id") ?? "").trim();
      const requestedLevel = Number(url.searchParams.get("level") ?? 0);
      if (!/^[0-9a-f-]{36}$/i.test(roomId) ||
          (launchId && !/^[0-9a-f-]{36}$/i.test(launchId)) ||
          (!launchId && (!Number.isSafeInteger(requestedLevel) || requestedLevel < 1 || requestedLevel > 150))) {
        return json({ error: "invalid_contributor_request" }, 400, origin, env);
      }
      const activeVisit = await db.prepare(
        "SELECT id FROM room_chat_visits WHERE room_id=? AND user_id=? AND exited_at IS NULL AND last_seen_at>=? LIMIT 1"
      ).bind(roomId, user.id, new Date(Date.now() - 45000).toISOString()).first<{ id: string }>();
      if (!activeVisit) return json({ error: "room_membership_required" }, 403, origin, env);
      let launch: { id: string; level: number; day: string } | null;
      if (launchId) {
        launch = await db.prepare(
          "SELECT id, level, day FROM cannon_launches WHERE id=? AND room_id=? LIMIT 1"
        ).bind(launchId, roomId).first<{ id: string; level: number; day: string }>();
      } else {
        launch = await db.prepare(
          "SELECT id, level, day FROM cannon_launches WHERE room_id=? AND day=? AND level=? ORDER BY created_at DESC LIMIT 1"
        ).bind(roomId, saudiDay(), requestedLevel).first<{ id: string; level: number; day: string }>();
        launchId = launch?.id ?? '';
      }
      if (!launch) return json({ ok: true, launch_id: '', level: requestedLevel || 0, contributors: [] }, 200, origin, env);
      let rows = await db.prepare(
        "SELECT c.user_id AS user_id, COALESCE(NULLIF(p.display_name,''), NULLIF(p.happy_id,''), 'مساهم') AS user_name, " +
        "COALESCE(p.avatar_key,'') AS avatar_url, COALESCE(p.happy_id,'') AS public_id, c.contribution AS contribution " +
        "FROM cannon_launch_contributors c LEFT JOIN profiles p ON p.user_id=c.user_id " +
        "WHERE c.launch_id=? AND c.room_id=? AND c.contribution>0 " +
        "ORDER BY c.contribution DESC, c.user_id ASC LIMIT 200"
      ).bind(launchId, roomId).all<Record<string, unknown>>();
      // Backward compatibility: older Worker versions created launches but did not
      // freeze their contributor rows. Use the retained per-level contribution ledger
      // for those launches so genuine contributors are not shown as empty cards.
      if (!(rows.results?.length)) {
        rows = await db.prepare(
          "SELECT c.user_id AS user_id, COALESCE(NULLIF(p.display_name,''), NULLIF(p.happy_id,''), 'مساهم') AS user_name, " +
          "COALESCE(p.avatar_key,'') AS avatar_url, COALESCE(p.happy_id,'') AS public_id, c.amount AS contribution " +
          "FROM cannon_contrib c LEFT JOIN profiles p ON p.user_id=c.user_id " +
          "WHERE c.room_id=? AND c.day=? AND c.level=? AND c.amount>0 " +
          "ORDER BY c.amount DESC, c.user_id ASC LIMIT 200"
        ).bind(roomId, launch.day, launch.level).all<Record<string, unknown>>();
      }
      return json({
        ok: true,
        launch_id: launch.id,
        level: launch.level,
        contributors: rows.results ?? []
      }, 200, origin, env);
    }

    if (url.pathname === "/api/cannon/banners" && request.method === "GET") {
      if (!settings.enabled || !settings.bannerEnabled) return json({ ok: true, banners: [] }, 200, origin, env);
      const day = saudiDay();
      const rows = await db.prepare(
        "SELECT c.room_id AS roomId, c.level AS cannonLevel, c.progress, c.launching_until AS launchingUntil, r.name AS title, COALESCE(p.avatar_key,'') AS avatar " +
        "FROM cannon_rooms c INNER JOIN rooms r ON r.id=c.room_id LEFT JOIN profiles p ON p.user_id=r.owner_user_id " +
        "WHERE c.day=? AND r.status='active' ORDER BY c.launching_until DESC, c.progress DESC LIMIT 30"
      ).bind(day).all<Record<string, unknown>>();
      const banners = (rows.results ?? []).flatMap(row => {
        const cfg = settings.levels.find(x => x.level === Number(row.cannonLevel));
        const need = cfg?.need ?? 0;
        const percent = need > 0 ? Math.min(100, Math.floor(Number(row.progress ?? 0) / need * 100)) : 0;
        const launching = Number(row.launchingUntil ?? 0) > nowSeconds();
        if (!launching && percent < 80) return [];
        return [{ room_id: row.roomId, title: row.title, avatar: row.avatar, text: launching ? "تم إطلاق المدفع!" : "اقترب إطلاق مدفع الغرفة", owner_level: 1, cannon_level: row.cannonLevel, percent, launching }];
      }).slice(0, 5);
      return json({ ok: true, banners, bannerImageUrl: settings.bannerImageUrl, frameImageUrl: settings.frameImageUrl }, 200, origin, env);
    }

    if (url.pathname === "/api/cannon/claim" && request.method === "POST") {
      let body: Record<string, unknown>;
      try { body = await request.json() as Record<string, unknown>; } catch { return json({ error: "invalid_json" }, 400, origin, env); }
      const claimId = typeof body.claim_id === "string" ? body.claim_id.trim() : "";
      if (!/^[0-9a-f-]{36}$/i.test(claimId)) return json({ error: "invalid_claim_id" }, 400, origin, env);
      const claim = await db.prepare(
        "SELECT id,user_id AS userId,reward_type AS rewardType,reward_value AS rewardValue,reward_name AS rewardName FROM cannon_claims WHERE id=? AND user_id=? AND claimed=0 LIMIT 1"
      ).bind(claimId, user.id).first<{ id: string; userId: string; rewardType: string; rewardValue: string; rewardName: string }>();
      if (!claim) return json({ error: "claim_not_found_or_claimed" }, 404, origin, env);
      const now = new Date().toISOString();
      const statements: D1PreparedStatement[] = [
        db.prepare("UPDATE cannon_claims SET claimed=1, claimed_at=? WHERE id=? AND user_id=? AND claimed=0").bind(now, claimId, user.id),
        db.prepare("INSERT OR IGNORE INTO user_wallets (user_id,balance,updated_at) SELECT ?,0,? WHERE ?='coins'").bind(user.id, now, claim.rewardType)
      ];
      if (claim.rewardType === "coins") {
        const amount = Number(claim.rewardValue);
        if (!Number.isSafeInteger(amount) || amount < 1 || amount > 1000000000) return json({ error: "invalid_coin_reward" }, 400, origin, env);
        statements.push(db.prepare(
          "UPDATE user_wallets SET balance=balance+?,updated_at=? WHERE user_id=? AND EXISTS (SELECT 1 FROM cannon_claims WHERE id=? AND user_id=? AND claimed=1) AND NOT EXISTS (SELECT 1 FROM cannon_wallet_ledger WHERE claim_id=?)"
        ).bind(amount, now, user.id, claimId, user.id, claimId));
        statements.push(db.prepare(
          "INSERT OR IGNORE INTO cannon_wallet_ledger (id,claim_id,user_id,amount,balance_after,created_at) SELECT ?, ?, ?, ?, balance, ? FROM user_wallets WHERE user_id=? AND EXISTS (SELECT 1 FROM cannon_claims WHERE id=? AND user_id=? AND claimed=1)"
        ).bind(crypto.randomUUID(), claimId, user.id, amount, now, user.id, claimId, user.id));
      } else {
        statements.push(db.prepare(
          "INSERT OR IGNORE INTO cannon_user_items (id,claim_id,user_id,item_id,item_name,created_at) SELECT ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM cannon_claims WHERE id=? AND user_id=? AND claimed=1)"
        ).bind(crypto.randomUUID(), claimId, user.id, claim.rewardValue, claim.rewardName, now, claimId, user.id));
      }
      const results = await db.batch(statements);
      if ((results[0]?.meta?.changes ?? 0) !== 1) return json({ error: "claim_already_processed" }, 409, origin, env);
      return json({ ok: true, claimed: true, reward: { type: claim.rewardType, value: claim.rewardValue, name: claim.rewardName } }, 200, origin, env);
    }

    return json({ error: "method_not_allowed" }, 405, origin, env);
  } catch (error) {
    console.error("[cannon] request failed", error instanceof Error ? error.message : "UnknownError");
    return json({ error: "cannon_unavailable" }, 503, origin, env);
  }
}
