'use strict';
const GAME_ID='f21d2c7a-8f1b-4d72-9a63-5c8f7e1d4b90';
const enc=new TextEncoder();
async function hash(v){const b=new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(v)));return Array.from(b,x=>x.toString(16).padStart(2,'0')).join('');}
export async function auth(db,token,origin,now=new Date().toISOString()){
 if(typeof token!=='string'||token.length<32||token.length>512||!origin)return null;
 const row=await db.prepare("SELECT s.id,s.user_id AS userId,s.game_origin AS gameOrigin FROM game_sessions s INNER JOIN game_session_app_bindings b ON b.game_session_id=s.id INNER JOIN user_sessions app ON app.id=b.app_session_id AND app.user_id=s.user_id AND app.revoked_at IS NULL AND app.expires_at>? INNER JOIN users u ON u.id=s.user_id INNER JOIN game_registry g ON g.id=s.game_id INNER JOIN game_registry_lifecycle l ON l.game_id=g.id WHERE s.token_hash=? AND s.revoked_at IS NULL AND s.expires_at>? AND s.game_id=? AND g.enabled=1 AND l.status='active' AND u.status='active' LIMIT 1").bind(now,await hash(token),now,GAME_ID).first();
 // Production origin is stored on the game session. Cloudflare Pages preview
 // deployments for this same project are trusted aliases of that production
 // origin, so they may exercise the same session without weakening the host
 // boundary to arbitrary *.pages.dev domains.
 let originMatches = Boolean(row && row.gameOrigin === origin);
 if (row && !originMatches) {
  try {
   const registered = new URL(row.gameOrigin);
   const supplied = new URL(origin);
   const isHappyLivePagesPreview = registered.protocol === 'https:' &&
    registered.hostname === 'happy-live.pages.dev' &&
    supplied.protocol === 'https:' &&
    supplied.port === '' &&
    supplied.hostname.endsWith('.happy-live.pages.dev') &&
    supplied.hostname !== 'happy-live.pages.dev';
   originMatches = isHappyLivePagesPreview;
  } catch {}
 }
 return row && originMatches ? row : null;
}
export async function profile(db,id){return db.prepare("SELECT COALESCE(p.display_name,'') AS name,COALESCE(p.avatar_key,'') AS avatar,COALESCE(p.happy_id,'') AS happyId FROM users u LEFT JOIN profiles p ON p.user_id=u.id WHERE u.id=? AND u.status='active' LIMIT 1").bind(id).first();}
export async function balance(db,id){const row=await db.prepare('SELECT balance FROM user_wallets WHERE user_id=? LIMIT 1').bind(id).first();if(!row)throw new Error('wallet_not_found');const value=Number(row.balance);if(!Number.isSafeInteger(value)||value<0)throw new Error('wallet_balance_invalid');return value;}
export async function debit(db,id,amount){if(!Number.isSafeInteger(amount)||amount<=0)return false;const r=await db.prepare('UPDATE user_wallets SET balance=balance-?,updated_at=? WHERE user_id=? AND balance>=?').bind(amount,new Date().toISOString(),id,amount).run();return Number(r.meta?.changes??0)===1;}
export async function credit(db,id,amount){if(!Number.isSafeInteger(amount)||amount<=0)return false;const r=await db.prepare('UPDATE user_wallets SET balance=balance+?,updated_at=? WHERE user_id=?').bind(amount,new Date().toISOString(),id).run();return Number(r.meta?.changes??0)===1;}
export function debitStatement(db,id,amount,now,roundId){return db.prepare("UPDATE user_wallets SET balance=balance-?,updated_at=? WHERE user_id=? AND balance>=? AND EXISTS(SELECT 1 FROM game_rounds WHERE id=? AND status='open')").bind(amount,now,id,amount,roundId);}
export function creditStatement(db,id,amount,now,roundId,settlementId){return db.prepare("UPDATE user_wallets SET balance=balance+?,updated_at=? WHERE user_id=? AND ?>0 AND EXISTS(SELECT 1 FROM game_rounds WHERE id=? AND status='settling' AND settlement_id=?)").bind(amount,now,id,amount,roundId,settlementId);}
