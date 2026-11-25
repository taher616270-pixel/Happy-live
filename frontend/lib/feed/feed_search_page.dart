import 'package:flutter/material.dart';
import 'feed_icons.dart';
import 'feed_models.dart';
import 'feed_repository.dart';
class FeedSearchPage extends StatefulWidget {final FeedRepository repo;const FeedSearchPage({super.key,required this.repo});@override State<FeedSearchPage> createState()=>_FeedSearchPageState();}
class _FeedSearchPageState extends State<FeedSearchPage>{
 final _t=TextEditingController();List<FeedVideo> _res=[];bool _loading=false,_searched=false;
 Future<void> _go() async {final q=_t.text.trim();if(q.isEmpty)return;setState((){_loading=true;_searched=true;});try{_res=await widget.repo.search(q);}catch(_){_res=[];}if(mounted)setState(()=>_loading=false);}
 @override void dispose(){_t.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Column(children:[
  Padding(padding:const EdgeInsets.fromLTRB(8,8,12,8),child:Row(children:[
   IconButton(icon:const Icon(Icons.chevron_right_rounded,color:Colors.white,size:32),onPressed:()=>Navigator.pop(context)),
   Expanded(child:TextField(controller:_t,autofocus:true,textInputAction:TextInputAction.search,onSubmitted:(_)=>_go(),style:const TextStyle(color:Colors.white,fontSize:15),decoration:InputDecoration(hintText:'بحث',hintStyle:const TextStyle(color:Color(0x99FFFFFF)),prefixIcon:const Icon(Icons.search_rounded,color:Color(0x99FFFFFF)),filled:true,fillColor:const Color(0xFF2A2A2D),isDense:true,contentPadding:const EdgeInsets.symmetric(vertical:11),border:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide.none)))),
   const SizedBox(width:10),GestureDetector(onTap:_go,child:const Text('بحث',style:TextStyle(color:kFeedRed,fontSize:16,fontWeight:FontWeight.w700)))
  ])),
  Expanded(child:_loading?const Center(child:CircularProgressIndicator(strokeWidth:2,color:Colors.white54)):_searched&&_res.isEmpty?const Center(child:Text('لا توجد نتائج',style:TextStyle(color:Colors.white54))):ListView.separated(itemCount:_res.length,separatorBuilder:(_,__)=>const Divider(height:1,color:Color(0x22FFFFFF)),itemBuilder:(_,i)=>ListTile(leading:CircleAvatar(backgroundColor:const Color(0xFF2A2A2D),backgroundImage:_res[i].authorAvatar.isNotEmpty?NetworkImage(_res[i].authorAvatar):null,child:_res[i].authorAvatar.isEmpty?const Icon(Icons.person,color:Colors.white54):null),title:Text(_res[i].authorName,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700)),subtitle:Text(_res[i].caption,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Color(0xB3FFFFFF))),onTap:()=>Navigator.pop(context,_res[i]))))
 ]))));
}
