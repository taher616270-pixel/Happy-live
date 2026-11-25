import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'feed_bottom_nav.dart';
import 'feed_comments_sheet.dart';
import 'feed_icons.dart';
import 'feed_item.dart';
import 'feed_models.dart';
import 'feed_repository.dart';
import 'feed_search_page.dart';
import 'feed_share_sheet.dart';
import 'feed_create_camera_page.dart';

class FeedScreen extends StatefulWidget {
 final FeedRepository repo; final bool showBottomNav; final bool isActive; final ValueChanged<int>? onNavTap; final VoidCallback? onLiveTap;
 const FeedScreen({super.key,required this.repo,this.showBottomNav=true,this.isActive=true,this.onNavTap,this.onLiveTap});
 @override State<FeedScreen> createState()=>_FeedScreenState();
}
class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
 final PageController _pc=PageController(); final Map<int,VideoPlayerController> _ctrls={}; final Map<int,String> _videoErrors={}; List<FeedVideo> _videos=[];
 FeedTab _tab=FeedTab.forYou; int _cur=0,_page=0; bool _loading=true,_more=false;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);_load();}
 @override void didUpdateWidget(covariant FeedScreen oldWidget){super.didUpdateWidget(oldWidget);if(oldWidget.isActive!=widget.isActive){if(widget.isActive){_sync();}else{for(final c in _ctrls.values){c.pause();}}}}
 @override void dispose(){WidgetsBinding.instance.removeObserver(this);for(final c in _ctrls.values){c.dispose();}_pc.dispose();super.dispose();}
 @override void didChangeAppLifecycleState(AppLifecycleState s){final c=_ctrls[_cur];if(c==null)return;if(s==AppLifecycleState.resumed&&widget.isActive){c.play();}else{c.pause();}}
 Future<void> _load() async {
  if(mounted)setState(()=>_loading=true);for(final c in _ctrls.values){c.dispose();}_ctrls.clear();_videoErrors.clear();_page=0;_cur=0;
  try{_videos=await widget.repo.feed(_tab);}catch(_){_videos=[];}
  if(!mounted)return;setState(()=>_loading=false);if(_pc.hasClients)_pc.jumpToPage(0);_sync();
 }
 Future<void> _ensure(int i) async {
  if (i < 0 || i >= _videos.length || _ctrls.containsKey(i)) return;
  _videoErrors.remove(i);
  // Photo posts are rendered directly by FeedItem; never initialize a video
  // decoder for an image URL (which leaves the feed spinner running forever).
  if (_videos[i].isImage) return;
  // Use the authenticated Worker media proxy instead of the raw ImageKit URL.
  // It forwards HTTP Range requests and exposes the byte-range headers Safari needs.
  final mediaUrl = '${FeedConfig.apiBase}/api/feed/media/${Uri.encodeComponent(_videos[i].id)}';
  final c=VideoPlayerController.networkUrl(
   Uri.parse(mediaUrl),
   httpHeaders: {'Authorization': 'Bearer ${FeedConfig.authToken()}'},
  );_ctrls[i]=c;
  try {
   await c.initialize().timeout(const Duration(seconds: 25));
   await c.setLooping(true);
  } catch (error) {
   // Publish the failed state before disposing the platform player. On web,
   // dispose() can itself wait on a stalled media element; awaiting it here
   // used to leave the feed spinner visible forever and hide the real error.
   if (_ctrls[i] == c) {
    _ctrls.remove(i);
    if (mounted) {
     setState(() => _videoErrors[i] = 'تعذر تحميل الفيديو. تحقق من صيغة الملف أو اتصال الشبكة.');
    }
   }
   // Cleanup must never block the UI/error state.
   c.dispose().catchError((_) {});
   return;
  }
  if(!mounted||_ctrls[i]!=c)return;setState((){});if(i==_cur&&widget.isActive){c.play();}else{c.pause();}
 }
 void _sync(){
  for(final k in _ctrls.keys.toList()){if((k-_cur).abs()>1){_ctrls.remove(k)?.dispose();}}
  _ensure(_cur);_ensure(_cur+1);_ensure(_cur-1);
  for(final e in _ctrls.entries){if(e.key==_cur&&widget.isActive){e.value.play();}else{e.value.pause();}}
 }
 Future<void> _onPage(int i) async {
  _cur=i;_sync();if(i>=_videos.length-2&&!_more){_more=true;try{final next=await widget.repo.feed(_tab,page:_page+1);if(next.isNotEmpty&&mounted){_page++;setState(()=>_videos.addAll(next));}}catch(_){} _more=false;}
 }
 void _setTab(FeedTab t){if(t==_tab)return;_tab=t;_load();}
 Future<void> _openCreator() async {
  // Open the native/browser file chooser directly inside the + tap gesture.
  // Navigating first can consume Safari's transient user activation.
  XFile? selected;
  try {
   selected = await ImagePicker().pickMedia();
  } catch (_) {
   if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
     const SnackBar(content: Text('تعذر فتح معرض الجهاز. حاول مرة أخرى.')),
    );
   }
   return;
  }
  if (!mounted || selected == null) return;
  final confirmed = await Navigator.of(context).push<bool>(
   MaterialPageRoute<bool>(
    builder: (_) => FeedCreateCameraPage(initialFile: selected!, accessToken: FeedConfig.authToken()),
   ),
  );
  if (confirmed == true && mounted) {
   await _load();
   if (!mounted) return;
   ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('تم نشر المنشور بنجاح')),
   );
  }
 }
 @override Widget build(BuildContext context){
  final top=MediaQuery.of(context).padding.top;
  return Directionality(textDirection:TextDirection.rtl,child:Scaffold(backgroundColor:Colors.black,body:Stack(children:[
   Column(children:[
    Expanded(child:_loading?const Center(child:CircularProgressIndicator(color:Colors.white54,strokeWidth:2)):_videos.isEmpty?const Center(child:Text('لا توجد فيديوهات حالياً',style:TextStyle(color:Colors.white54))):PageView.builder(controller:_pc,scrollDirection:Axis.vertical,itemCount:_videos.length,onPageChanged:_onPage,itemBuilder:(_,i){final v=_videos[i];return FeedItem(key:ValueKey(v.id),video:v,ctrl:_ctrls[i],videoError:_videoErrors[i],onRetry:(){setState(()=>_videoErrors.remove(i));_ensure(i);},repo:widget.repo,onComments:()=>showFeedComments(context,widget.repo,v,()=>setState((){})),onShare:()=>showFeedShare(context,widget.repo,v,()=>setState(()=>v.shares++)));})),
    if(widget.showBottomNav)FeedBottomNav(current:0,onTap:widget.onNavTap)
   ]),
   Positioned(top:top+6,left:0,right:0,height:44,child:Stack(alignment:Alignment.center,children:[
    Align(alignment:Alignment.centerLeft,child:IconButton(padding:const EdgeInsets.symmetric(horizontal:16),icon:const Icon(Icons.search_rounded,color:Colors.white,size:30),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FeedSearchPage(repo:widget.repo))))),
    Row(mainAxisSize:MainAxisSize.min,children:[_CreateButton(onTap:_openCreator),const SizedBox(width:20),_TabText('أتابعه',_tab==FeedTab.following,()=>_setTab(FeedTab.following)),const SizedBox(width:20),_TabText('لك',_tab==FeedTab.forYou,()=>_setTab(FeedTab.forYou))]),
    Align(alignment:Alignment.centerRight,child:GestureDetector(onTap:widget.onLiveTap,child:const Padding(padding:EdgeInsets.symmetric(horizontal:16),child:LiveIcon())))
   ]))
  ])));
 }
}
class _CreateButton extends StatelessWidget {
 final VoidCallback onTap;
 const _CreateButton({required this.onTap});
 @override Widget build(BuildContext context)=>Material(
  color:Colors.transparent,
  child:InkWell(
   onTap:onTap,
   borderRadius:BorderRadius.circular(10),
   child:Container(
    width:34,height:34,
    decoration:BoxDecoration(color:Colors.white.withOpacity(.16),borderRadius:BorderRadius.circular(10),border:Border.all(color:Colors.white.withOpacity(.8),width:1.2)),
    child:const Icon(Icons.add_rounded,color:Colors.white,size:27),
   ),
  ),
 );
}
class _TabText extends StatelessWidget {
 final String text;final bool selected;final VoidCallback onTap;const _TabText(this.text,this.selected,this.onTap);
 @override Widget build(BuildContext context)=>GestureDetector(behavior:HitTestBehavior.opaque,onTap:onTap,child:Column(mainAxisSize:MainAxisSize.min,children:[Text(text,style:TextStyle(color:selected?Colors.white:const Color(0xB3FFFFFF),fontSize:16.5,fontWeight:selected?FontWeight.w700:FontWeight.w500,shadows:const[Shadow(color:Color(0x66000000),blurRadius:4)])),const SizedBox(height:4),Container(width:28,height:2.5,color:selected?Colors.white:Colors.transparent)]));
}
