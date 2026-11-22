import {createClient} from '@supabase/supabase-js';
import {useEffect,useState,useCallback,useRef} from 'react';
import config from './supabase-config.json';
export const supabase=createClient(config.url,config.key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
export const MAX_FILE=20*1024*1024;
export function checked(result){if(result.error)throw result.error;return result.data;}
export async function uploadMedia(file,userId,privateChat=false){
 if(!file)throw new Error('Choose a photo or video first.');
 if(!['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm'].includes(file.type))throw new Error('Choose a JPG, PNG, WebP, GIF, MP4 or WebM file.');
 if(file.size>MAX_FILE)throw new Error('This demo accepts files up to 20 MB. Please choose a smaller file.');
 const ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp','image/gif':'gif','video/mp4':'mp4','video/webm':'webm'}[file.type];
 const bucket=privateChat?'chat-media':'media',path=`${userId}/${crypto.randomUUID()}.${ext}`;
 checked(await supabase.storage.from(bucket).upload(path,file,{cacheControl:'3600',contentType:file.type,upsert:false}));
 const url=privateChat?`${config.url}/storage/v1/object/authenticated/chat-media/${path}`:supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl;
 return {url,type:file.type.startsWith('video/')?'video':'image',path,bucket};
}
export async function privateMediaUrl(url){
 if(!url)return null;
 const prefix=`${config.url}/storage/v1/object/authenticated/chat-media/`;
 if(!url.startsWith(prefix))throw new Error('Invalid private attachment.');
 return checked(await supabase.storage.from('chat-media').createSignedUrl(url.slice(prefix.length),300)).signedUrl;
}
export async function removeMedia(url){
 if(!url)return;
 for(const [bucket,kind] of [['media','public'],['chat-media','authenticated']]){
  const prefix=`${config.url}/storage/v1/object/${kind}/${bucket}/`;
  if(url.startsWith(prefix)){checked(await supabase.storage.from(bucket).remove([url.slice(prefix.length)]));return;}
 }
}
export function useData(session){
 const activeUid=useRef(session?.user.id);activeUid.current=session?.user.id;
 const [data,setData]=useState({profiles:[],posts:[],likes:[],comments:[],follows:[],saves:[],friends:[],stories:[],notifications:[],messages:[]});
 const [loading,setLoading]=useState(true),[error,setError]=useState('');
 const refresh=useCallback(async()=>{
  const uid=session?.user.id;
  try{
   const names=['profiles','posts','likes','comments','follows','stories',...(uid?['saves','friendships','notifications','messages']:[])];
   const results=await Promise.all(names.map(name=>{
    let q=supabase.from(name).select('*');
    if(name==='posts')q=q.order('created_at',{ascending:false}).limit(100);
    if(name==='comments')q=q.order('created_at',{ascending:true}).limit(1000);
    if(name==='stories')q=q.gt('expires_at',new Date().toISOString()).order('created_at',{ascending:false});
    if(name==='notifications'||name==='messages')q=q.order('created_at',{ascending:false}).limit(300);
    return q;
   }));
   const next={profiles:[],posts:[],likes:[],comments:[],follows:[],saves:[],friends:[],stories:[],notifications:[],messages:[]};
   names.forEach((n,i)=>{next[n==='friendships'?'friends':n]=checked(results[i])||[];});
   if(activeUid.current!==uid)return;next.ownerId=uid;setData(next);setError('');
  }catch(e){setError(e.message||'Could not load your feed. Try again.');}finally{setLoading(false);}
 },[session?.user.id]);
 useEffect(()=>{refresh();const focus=()=>refresh();window.addEventListener('focus',focus);return()=>window.removeEventListener('focus',focus);},[refresh]);
 useEffect(()=>{
  if(!session)return;
  let timer;const channel=supabase.channel('app-'+session.user.id).on('postgres_changes',{event:'*',schema:'public'},()=>{clearTimeout(timer);timer=setTimeout(refresh,250);}).subscribe();
  return()=>{clearTimeout(timer);supabase.removeChannel(channel);};
 },[session?.user.id,refresh]);
 const visible={...data};if(data.ownerId!==session?.user.id)for(const key of ['saves','friends','messages','notifications'])visible[key]=[];return{...visible,loading,error,refresh};
}
export function timeAgo(value){const n=Math.max(0,Math.floor((Date.now()-new Date(value))/1000));if(n<60)return 'now';if(n<3600)return Math.floor(n/60)+'m';if(n<86400)return Math.floor(n/3600)+'h';return Math.floor(n/86400)+'d';}
export function safeWebsite(value){try{const u=new URL(value);return ['https:','http:'].includes(u.protocol)?u.href:null;}catch{return null;}}
