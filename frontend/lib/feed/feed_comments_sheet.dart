import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:characters/characters.dart';
import 'feed_icons.dart';
import 'feed_models.dart';
import 'feed_repository.dart';
Future<void> showFeedComments(BuildContext context,FeedRepository repo,FeedVideo video,VoidCallback onChanged)=>showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(_)=>Directionality(textDirection:TextDirection.rtl,child:_CommentsSheet(repo:repo,video:video,onChanged:onChanged)));
const _ink=Color(0xFF161823),_gray=Color(0xFF8A8B91),_field=Color(0xFFF1F1F2);
const _emojis=['👑👑👑','😂😂😂','😁😁😁','🥰🥰🥰','😳😳😳','🔥🔥🔥','❤️❤️❤️'];
class _CommentsSheet extends StatefulWidget {
 final FeedRepository repo;final FeedVideo video;final VoidCallback onChanged;
 const _CommentsSheet({required this.repo,required this.video,required this.onChanged});
 @override State<_CommentsSheet> createState()=>_CommentsSheetState();
}
class _CommentsSheetState extends State<_CommentsSheet>{
 final _t=TextEditingController();final _f=FocusNode();List<FeedComment> _list=[];bool _loading=true;
 @override void initState(){super.initState();widget.repo.comments(widget.video.id).then((l){if(mounted)setState((){_list=l;_loading=false;});}).catchError((_){if(mounted)setState(()=>_loading=false);});_t.addListener(()=>setState((){}));}
 @override void dispose(){_t.dispose();_f.dispose();super.dispose();}
 Future<void> _send() async {final text=_t.text.trim();if(text.isEmpty)return;_t.clear();try{final c=await widget.repo.addComment(widget.video.id,text);if(!mounted)return;setState((){_list.insert(0,c);widget.video.comments++;});widget.onChanged();}catch(_){}}
 @override Widget build(BuildContext context){
  final mq=MediaQuery.of(context);final kb=mq.viewInsets.bottom;final h=math.min(mq.size.height*.68,mq.size.height-kb-mq.padding.top-20);final hasText=_t.text.trim().isNotEmpty;
  return Padding(padding:EdgeInsets.only(bottom:kb),child:Container(height:h,decoration:const BoxDecoration(color:Colors.white,borderRadius:BorderRadius.vertical(top:Radius.circular(14))),child:Column(children:[
   SizedBox(height:48,child:Stack(alignment:Alignment.center,children:[Text(widget.video.comments==0?'تعليقات':'${fmtCount(widget.video.comments)} تعليقات',style:const TextStyle(color:_ink,fontSize:14.5,fontWeight:FontWeight.w700)),Align(alignment:Alignment.centerLeft,child:IconButton(icon:const Icon(Icons.close_rounded,color:_ink,size:24),onPressed:()=>Navigator.pop(context)))])),
   Expanded(child:_loading?const Center(child:CircularProgressIndicator(strokeWidth:2,color:_gray)):_list.isEmpty?_empty():ListView.builder(padding:const EdgeInsets.fromLTRB(16,4,16,12),itemCount:_list.length,itemBuilder:(_,i)=>_CommentTile(c:_list[i],repo:widget.repo))),
   SizedBox(height:44,child:ListView.separated(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),itemCount:_emojis.length,separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(_,i)=>GestureDetector(onTap:(){final e=_emojis[i].characters.first;_t.text+=e;_t.selection=TextSelection.collapsed(offset:_t.text.length);},child:Container(padding:const EdgeInsets.symmetric(horizontal:14),alignment:Alignment.center,decoration:BoxDecoration(color:_field,borderRadius:BorderRadius.circular(18)),child:Text(_emojis[i],style:const TextStyle(fontSize:18)))))),
   Padding(padding:const EdgeInsets.fromLTRB(12,4,12,0),child:Row(children:[
    CircleAvatar(radius:18,backgroundColor:const Color(0xFFE6E6EA),backgroundImage:FeedConfig.myAvatar().isNotEmpty?NetworkImage(FeedConfig.myAvatar()):null,child:FeedConfig.myAvatar().isEmpty?const Icon(Icons.person,color:_gray,size:20):null),
    const SizedBox(width:10),Expanded(child:TextField(controller:_t,focusNode:_f,minLines:1,maxLines:4,textInputAction:TextInputAction.send,onSubmitted:(_)=>_send(),style:const TextStyle(color:_ink,fontSize:14.5),decoration:InputDecoration(hintText:'إضافة تعليق...',hintStyle:const TextStyle(color:_gray,fontSize:14.5),filled:true,fillColor:_field,isDense:true,contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:12),border:OutlineInputBorder(borderRadius:BorderRadius.circular(20),borderSide:BorderSide.none))))
   ])),
   Padding(padding:EdgeInsets.fromLTRB(14,8,14,8+(kb>0?0:mq.padding.bottom)),child:Row(children:[
    const Icon(Icons.image_outlined,color:_ink,size:26),const SizedBox(width:16),const Icon(Icons.emoji_emotions_outlined,color:_ink,size:26),const SizedBox(width:16),const Icon(Icons.alternate_email_rounded,color:_ink,size:26),const SizedBox(width:16),const Icon(Icons.mic_none_rounded,color:_ink,size:27),const Spacer(),
    GestureDetector(onTap:hasText?_send:null,child:Container(width:54,height:32,decoration:BoxDecoration(color:hasText?kFeedRed:const Color(0xFFFFB3C1),borderRadius:BorderRadius.circular(16)),child:const Icon(Icons.arrow_upward_rounded,color:Colors.white,size:22)))
   ]))
  ])));
 }
 Widget _empty()=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Stack(alignment:Alignment.center,children:[Icon(Icons.chat_bubble_outline_rounded,size:64,color:Color(0xFFD2D3D7)),Positioned(bottom:0,left:0,child:Icon(Icons.sentiment_satisfied_alt_outlined,size:40,color:Color(0xFFD2D3D7)))]),const SizedBox(height:18),const Text('هل تستمتع بهذا المنشور؟ كن أول من يعلق',style:TextStyle(color:_gray,fontSize:14)),const SizedBox(height:18),GestureDetector(onTap:_f.requestFocus,child:Container(width:128,height:42,alignment:Alignment.center,decoration:BoxDecoration(color:_field,borderRadius:BorderRadius.circular(8)),child:const Text('تعليق',style:TextStyle(color:_ink,fontSize:15,fontWeight:FontWeight.w700))))]));
}
class _CommentTile extends StatefulWidget {final FeedComment c;final FeedRepository repo;const _CommentTile({required this.c,required this.repo});@override State<_CommentTile> createState()=>_CommentTileState();}
class _CommentTileState extends State<_CommentTile>{
 @override Widget build(BuildContext context){final c=widget.c;return Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
  CircleAvatar(radius:18,backgroundColor:const Color(0xFFE6E6EA),backgroundImage:c.avatar.isNotEmpty?NetworkImage(c.avatar):null,child:c.avatar.isEmpty?const Icon(Icons.person,color:_gray,size:20):null),const SizedBox(width:10),
  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(c.user,style:const TextStyle(color:_gray,fontSize:13,fontWeight:FontWeight.w600)),const SizedBox(height:2),Text(c.text,style:const TextStyle(color:_ink,fontSize:14.5,height:1.35)),const SizedBox(height:6),Row(children:[Text(c.time,style:const TextStyle(color:_gray,fontSize:12.5)),const SizedBox(width:18),const Text('رد',style:TextStyle(color:_gray,fontSize:12.5,fontWeight:FontWeight.w700))]) ])),
  GestureDetector(onTap:(){setState((){c.liked=!c.liked;c.likes+=c.liked?1:-1;});widget.repo.likeComment(c.id,c.liked).catchError((_){});},child:Column(children:[Icon(c.liked?Icons.favorite_rounded:Icons.favorite_border_rounded,size:20,color:c.liked?kFeedRed:_gray),if(c.likes>0)Text('${c.likes}',style:const TextStyle(color:_gray,fontSize:12))]))
 ]));}
}
