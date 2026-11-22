export const USERNAME_RULES='3-24 characters: a-z, 0-9, dots (.) or underscores (_). A leading @ is removed.';
// Keep invalid internal characters visible so the user can correct them.
export function normalizeUsername(value){return String(value).replace(/^@+/, '').toLowerCase()}
export function usernameError(value){
 const username=normalizeUsername(String(value).trim());
 if(username.length<3)return 'Use at least 3 characters. For example: yy1 or abdo_2026.';
 if(username.length>24)return 'Use no more than 24 characters.';
 if(!/^[a-z0-9_.]{3,24}$/.test(username))return 'Use only a-z, 0-9, dots (.) or underscores (_). No spaces or other symbols.';
 return '';
}
