import {createClient} from '@supabase/supabase-js';
import config from '../src/supabase-config.json' with {type:'json'};
import {readFile,writeFile} from 'node:fs/promises';
const clients=[],ids=[],passed=[];
function ck(r){if(r.error)throw r.error;return r.data}
function assert(x,m){if(!x)throw Error(m)}
const c=()=>createClient(config.url,config.key,{auth:{persistSession:false,autoRefreshToken:false}});
try{
 for(let i=0;i<3;i++){const s=c();const a=ck(await s.auth.signInAnonymously());clients.push(s);ids.push(a.user.id)}
 const[a,b,z]=clients,[A,B,Z]=ids;passed.push('three distinct real anonymous auth accounts');
 await writeFile('/tmp/instagram-qa-ids.json',JSON.stringify(ids));
 ck(await a.from('profiles').update({full_name:'QA Creator A',bio:'Temporary integration-test account.'}).eq('id',A));
 const original=ck(await a.from('profiles').select('*').eq('id',A).single());assert(original.full_name==='QA Creator A','profile did not persist');passed.push('profile update persists');
 const invalid=await a.from('profiles').update({is_seed:true}).eq('id',A);assert(invalid.error,'client can forge seed status');passed.push('seed/admin field cannot be forged');
 ck(await a.rpc('request_friend',{target:B}));let f=ck(await b.from('friendships').select('*').eq('requester_id',A).single());assert(f.status==='pending','friend request state');
 assert(ck(await z.from('friendships').select('*').eq('requester_id',A)).length===0,'outsider sees private friendship');
 ck(await b.rpc('respond_friend',{friendship:f.id,accept:true}));f=ck(await a.from('friendships').select('*').eq('id',f.id).single());assert(f.status==='accepted','accept not persisted');
 ck(await a.rpc('remove_friend',{target:B}));assert(ck(await b.from('friendships').select('*').eq('id',f.id)).length===0,'remove friend failed');passed.push('friend add, private list, accept, remove');
 ck(await a.from('follows').insert({follower_id:A,following_id:B}));assert(ck(await b.from('follows').select('*').eq('follower_id',A)).length===1,'follow missing');ck(await a.from('follows').delete().eq('follower_id',A).eq('following_id',B));passed.push('follow and unfollow');
 const image=await readFile('public/seed/photo-10.jpg'),ip=A+'/qa-image.jpg';ck(await a.storage.from('media').upload(ip,image,{contentType:'image/jpeg'}));const imageUrl=a.storage.from('media').getPublicUrl(ip).data.publicUrl;
 const post=ck(await a.from('posts').insert({user_id:A,caption:'QA image upload',media_url:imageUrl,media_type:'image'}).select().single());
 const spoof=await b.from('posts').insert({user_id:A,caption:'bad',media_url:imageUrl,media_type:'image'});assert(spoof.error,'spoofed post accepted');
 ck(await b.from('posts').delete().eq('id',post.id));assert(ck(await a.from('posts').select('id').eq('id',post.id)).length===1,'other account deleted post');passed.push('real image storage/post + cross-account ownership denial');
 ck(await b.from('likes').insert({post_id:post.id,user_id:B}));ck(await b.from('saves').insert({post_id:post.id,user_id:B}));assert(ck(await a.from('saves').select('*').eq('post_id',post.id)).length===0,'saved posts leaked');
 const comment=ck(await b.from('comments').insert({post_id:post.id,user_id:B,body:'QA cross-account comment'}).select().single());ck(await z.from('comments').delete().eq('id',comment.id));assert(ck(await b.from('comments').select('id').eq('id',comment.id)).length===1,'outsider deleted comment');passed.push('likes, private saves, comments ownership');
 const video=await readFile('public/seed/coast-loop.mp4'),vp=A+'/qa-video.mp4';ck(await a.storage.from('media').upload(vp,video,{contentType:'video/mp4'}));const videoUrl=a.storage.from('media').getPublicUrl(vp).data.publicUrl;
 const reel=ck(await a.from('posts').insert({user_id:A,caption:'QA video upload',media_url:videoUrl,media_type:'video'}).select().single());assert((await fetch(videoUrl,{method:'HEAD'})).ok,'video cannot play');passed.push('real MP4 storage and reel record');
 const story=ck(await a.from('stories').insert({user_id:A,media_url:imageUrl,media_type:'image',caption:'QA story'}).select().single());assert(new Date(story.expires_at)-new Date(story.created_at)<=86401000,'story expiry wrong');passed.push('persisted 24-hour story');
 const chatPath=A+'/qa-private.jpg';ck(await a.storage.from('chat-media').upload(chatPath,image,{contentType:'image/jpeg'}));const chatUrl=config.url+'/storage/v1/object/authenticated/chat-media/'+chatPath;
 const message=ck(await a.from('messages').insert({sender_id:A,recipient_id:B,body:'QA private hello',media_url:chatUrl,media_type:'image'}).select().single());
 assert(ck(await b.from('messages').select('*').eq('id',message.id)).length===1,'recipient cannot read message');assert(ck(await z.from('messages').select('*').eq('id',message.id)).length===0,'outsider sees message');
 ck(await b.storage.from('chat-media').createSignedUrl(chatPath,60));const forbidden=await z.storage.from('chat-media').createSignedUrl(chatPath,60);assert(forbidden.error,'outsider signs private media');
 const publicUrl=config.url+'/storage/v1/object/public/chat-media/'+chatPath;const publicRead=await fetch(publicUrl);assert(!publicRead.ok,'private media publicly readable');
 const impersonate=await z.from('messages').insert({sender_id:A,recipient_id:B,body:'forged'});assert(impersonate.error,'outsider can impersonate sender');
 ck(await b.rpc('mark_messages_read',{sender:A}));assert(ck(await a.from('messages').select('read_at').eq('id',message.id).single()).read_at,'read receipt missing');passed.push('private chat delivery, private attachment, read receipt, outsider and forged-sender denial');
 const privateVideo=A+'/qa-private.mp4';ck(await a.storage.from('chat-media').upload(privateVideo,video,{contentType:'video/mp4'}));const mv=ck(await a.from('messages').insert({sender_id:A,recipient_id:B,body:'',media_url:config.url+'/storage/v1/object/authenticated/chat-media/'+privateVideo,media_type:'video'}).select().single());ck(await b.storage.from('chat-media').createSignedUrl(privateVideo,60));passed.push('private video messages');
 assert(ck(await b.from('notifications').select('*')).length>0,'notifications missing');assert(ck(await z.from('notifications').select('*').eq('recipient_id',B)).length===0,'notifications leaked');passed.push('notifications and recipient-only access');
 ck(await a.from('posts').update({caption:'Edited caption'}).eq('id',post.id));assert(ck(await a.from('posts').select('caption').eq('id',post.id).single()).caption==='Edited caption','edit failed');
 ck(await a.from('posts').delete().eq('id',post.id));assert(ck(await b.from('comments').select('*').eq('post_id',post.id)).length===0,'delete did not cascade comments');passed.push('post edit/delete cascade');
 console.log(JSON.stringify({passed,qaAccounts:ids.length},null,2));
 await writeFile('/downloads/instagram-supabase-integration-results.json',JSON.stringify({passed,testedAt:new Date().toISOString()},null,2));
}finally{
 for(let i=0;i<clients.length;i++){try{for(const bucket of ['media','chat-media']){const rows=ck(await clients[i].storage.from(bucket).list(ids[i],{limit:100}));if(rows.length)ck(await clients[i].storage.from(bucket).remove(rows.map(x=>ids[i]+'/'+x.name)))}ck(await clients[i].rpc('delete_my_account'));await clients[i].auth.signOut()}catch(e){console.error('QA cleanup requires follow-up for account',ids[i],e.message)}}
}
