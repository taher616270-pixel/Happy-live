export interface ChickenRoadSession { id:string; userId:string; gameOrigin:string; }
export function auth(db:D1Database,token:string,origin:string,now?:string):Promise<ChickenRoadSession|null>;
export function profile(db:D1Database,id:string):Promise<{name:string;avatar:string;happyId:string}|null>;
export function balance(db:D1Database,id:string):Promise<number>;
export function debit(db:D1Database,id:string,amount:number):Promise<boolean>;
export function credit(db:D1Database,id:string,amount:number):Promise<boolean>;
export function debitStatement(db:D1Database,id:string,amount:number,now:string,roundId:string):D1PreparedStatement;
export function creditStatement(db:D1Database,id:string,amount:number,now:string,roundId:string,settlementId:string):D1PreparedStatement;