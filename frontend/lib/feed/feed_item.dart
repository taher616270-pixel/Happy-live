import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'feed_icons.dart';
import 'feed_models.dart';
import 'feed_repository.dart';
class _Burst {final int id;final Offset pos;final double angle;_Burst(this.id,this.pos,this.angle);}
class FeedItem extends StatefulWidget {
 final FeedVideo video;final VideoPlayerController? ctrl;final String? videoError;final VoidCallback onRetry;final FeedRepository repo;final VoidCallback onComments,onShare;
 const FeedItem({super.key,required this.video,required this.ctrl,this.videoError,required this.onRetry,required this.repo,required this.onComments,required this.onShare});
 @override State<FeedItem> createState()=>_FeedItemState();
}
class _FeedItemState extends State<FeedItem> with TickerProviderStateMixin {
 late final AnimationController _likePop=AnimationController(vsync:this,duration:const Duration(milliseconds:450));
 late final AnimationController _savePop=AnimationController(vsync:this,duration:const Duration(milliseconds:450));
 final List<_Burst> _bursts=[];int _burstId=0;DateTime? _lastTap;Timer? _single;bool _paused=false,_expanded=false;
 FeedVideo get v=>widget.video;
 @override void dispose(){_single?.cancel();_likePop.dispose();_savePop.dispose();super.dispose();}
 void _toggleLike(){setState((){v.liked=!v.liked;v.likes+=v.liked?1:-1;});if(v.liked)_likePop.forward(from:0);widget.repo.setLike(v.id,v.liked).catchError((_){});}
 void _toggleSave(){setState((){v.saved=!v.saved;v.saves+=v.saved?1:-1;});if(v.saved)_savePop.forward(from:0);widget.repo.setSave(v.id,v.saved).catchError((_){});}
 void _follow(){setState(()=>v.following=true);widget.repo.follow(v.id).catchError((_){});}
 void _tapUp(TapUpDetails d){
  final now=DateTime.now();
  if(_lastTap!=null&&now.difference(_lastTap!)<const Duration(milliseconds:280)){
   _single?.cancel();_lastTap=null;final b=_Burst(_burstId++,d.localPosition,(math.Random().nextDouble()-.5)*.5);setState(()=>_bursts.add(b));if(!v.liked)_toggleLike();
  }else{
   _lastTap=now;
   final c=widget.ctrl;
   if(c!=null&&!c.value.isPlaying){
    // Call play synchronously from the tap event; delaying it in a Timer
    // loses Safari's transient user activation and Safari rejects playback.
    if(kIsWeb)c.setVolume(1);
    c.play();
    if(mounted)setState(()=>_paused=false);
   }else{
    _single=Timer(const Duration(milliseconds:280),(){
     _lastTap=null;
     if(c==null||!mounted)return;
     if(c.value.isPlaying){c.pause();setState(()=>_paused=true);}
    });
   }
  }
 }
 @override Widget build(BuildContext context){
  final c=widget.ctrl;final ready=c!=null&&c.value.isInitialized;final landscape=ready&&c.value.aspectRatio>1.05;
  return Stack(fit:StackFit.expand,children:[
   const ColoredBox(color:Colors.black),
   if (v.isImage)
    Positioned.fill(
     child: Image.network(
      v.url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
       if (wasSynchronouslyLoaded || frame != null) return child;
       return const Center(
        child: SizedBox(
         width: 26,
         height: 26,
         child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
       );
      },
      errorBuilder: (context, error, stackTrace) => const Center(
       child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
         Icon(Icons.broken_image_outlined, color: Colors.white70, size: 42),
         SizedBox(height: 8),
         Text('تعذر تحميل الصورة', style: TextStyle(color: Colors.white70)),
        ],
       ),
      ),
     ),
    )
   else if (ready)
    (landscape
     ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
     : FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
         width: c.value.size.width,
         height: c.value.size.height,
         child: VideoPlayer(c),
        ),
       ))
   else if (widget.videoError != null)
    Center(child: Column(mainAxisSize:MainAxisSize.min,children:[
     const Icon(Icons.error_outline_rounded,color:Colors.white70,size:42),
     const SizedBox(height:10),
     const Text('تعذر تشغيل الفيديو',style:TextStyle(color:Colors.white,fontSize:15)),
     const SizedBox(height:8),
     TextButton.icon(onPressed:widget.onRetry,icon:const Icon(Icons.refresh,color:Colors.white),label:const Text('إعادة المحاولة',style:TextStyle(color:Colors.white))),
    ]))
   else
    const Center(
     child: SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
     ),
    ),
   const Positioned(left:0,right:0,bottom:0,height:220,child:IgnorePointer(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0x00000000),Color(0x99000000)]))))),
   Positioned.fill(child:GestureDetector(behavior:HitTestBehavior.translucent,onTapUp:_tapUp)),
   if(_paused)const IgnorePointer(child:Center(child:Icon(Icons.play_arrow_rounded,color:Color(0xCCFFFFFF),size:90))),
   for(final b in _bursts)_burstWidget(b),
   if(ready)Positioned(left:0,right:0,bottom:0,height:2,child:ValueListenableBuilder<VideoPlayerValue>(valueListenable:c,builder:(_,val,__){final d=val.duration.inMilliseconds;final p=d==0?0.0:(val.position.inMilliseconds/d).clamp(0.0,1.0).toDouble();return Directionality(textDirection:TextDirection.ltr,child:Align(alignment:Alignment.centerLeft,child:FractionallySizedBox(widthFactor:p,child:Container(height:2,color:Colors.white))));})),
   Positioned(left:8,bottom:14,child:_rail()),Positioned(right:12,left:84,bottom:12,child:_caption())
  ]);
 }
 Widget _burstWidget(_Burst b)=>Positioned(key:ValueKey(b.id),left:b.pos.dx-60,top:b.pos.dy-60,child:IgnorePointer(child:TweenAnimationBuilder<double>(tween:Tween(begin:0,end:1),duration:const Duration(milliseconds:800),onEnd:(){if(mounted)setState(()=>_bursts.removeWhere((x)=>x.id==b.id));},builder:(_,t,__) {final scale = t < 0.25 ? 0.4 + (t / 0.25) * 0.8 : 1.2 - 0.2 * ((t - 0.25) / 0.75);final op=t<.6?1.0:(1-(t-.6)/.4).clamp(0.0,1.0).toDouble();return Opacity(opacity:op,child:Transform.translate(offset:Offset(0,-50*t),child:Transform.rotate(angle:b.angle,child:Transform.scale(scale:scale,child:const Icon(Icons.favorite_rounded,color:kFeedRed,size:120,shadows:[Shadow(color:Color(0x66000000),blurRadius:14)])))));})));
 Widget _rail(){
  const shadow=[Shadow(color:Color(0x66000000),blurRadius:4)];
  Widget label(String t)=>Text(t,style:const TextStyle(color:Colors.white,fontSize:12.5,fontWeight:FontWeight.w600,shadows:shadow));
  Widget pop(AnimationController c,Widget child)=>AnimatedBuilder(animation:c,builder:(_,__)=>Transform.scale(scale:1+.4*math.sin(math.pi*c.value),child:child));
  Widget item(Widget icon,String text,VoidCallback tap)=>GestureDetector(behavior:HitTestBehavior.opaque,onTap:tap,child:Padding(padding:const EdgeInsets.only(bottom:18),child:Column(mainAxisSize:MainAxisSize.min,children:[icon,const SizedBox(height:4),label(text)])));
  return Column(mainAxisSize:MainAxisSize.min,children:[
   Padding(padding:EdgeInsets.only(bottom:v.following?20:30),child:Stack(clipBehavior:Clip.none,alignment:Alignment.bottomCenter,children:[
    Container(width:52,height:52,padding:const EdgeInsets.all(2),decoration:const BoxDecoration(shape:BoxShape.circle,gradient:LinearGradient(colors:[kFeedCyan,Color(0xFF2F6BFF),Color(0xFF3DDC84)])),child:ClipOval(child:v.authorAvatar.isEmpty?Container(color:const Color(0xFF2A2A2E),child:const Icon(Icons.person,color:Colors.white54)):Image.network(v.authorAvatar,fit:BoxFit.cover))),
    if(!v.following)Positioned(bottom:-10,child:GestureDetector(onTap:_follow,child:Container(width:22,height:22,decoration:const BoxDecoration(shape:BoxShape.circle,color:kFeedRed),child:const Icon(Icons.add_rounded,color:Colors.white,size:16))))
   ])),
   item(pop(_likePop,Icon(Icons.favorite_rounded,size:36,color:v.liked?kFeedRed:Colors.white,shadows:shadow)),fmtCount(v.likes),_toggleLike),
   item(const CommentDotsIcon(size:36),v.comments==0?'الأول':fmtCount(v.comments),widget.onComments),
   item(pop(_savePop,Icon(Icons.bookmark_rounded,size:36,color:v.saved?kFeedYellow:Colors.white,shadows:shadow)),fmtCount(v.saves),_toggleSave),
   item(Transform(alignment:Alignment.center,transform:Matrix4.diagonal3Values(-1,1,1),child:const Icon(Icons.reply_rounded,size:38,color:Colors.white,shadows:shadow)),v.shares==0?'مشاركة':fmtCount(v.shares),widget.onShare),
   const SpinDisc()
  ]);
 }
 Widget _caption(){
  const shadow=[Shadow(color:Color(0x88000000),blurRadius:4)];
  Widget pill(IconData icon,String text)=>Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:const Color(0x66000000),borderRadius:BorderRadius.circular(6)),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,color:Colors.white,size:16),const SizedBox(width:6),Text(text,style:const TextStyle(color:Colors.white,fontSize:12.5))]));
  return Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
   if(v.repostLabel!=null)pill(Icons.repeat_rounded,v.repostLabel!),
   if(v.template!=null)pill(Icons.movie_creation_outlined,'${v.template} · جرب هذا القالب'),
   Text(v.authorName,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800,shadows:shadow)),
   const SizedBox(height:4),
   GestureDetector(onTap:()=>setState(()=>_expanded=!_expanded),child:Text(v.caption,maxLines:_expanded?8:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:14,height:1.35,shadows:shadow))),
   if(v.sound.isNotEmpty)...[const SizedBox(height:6),Row(children:[const Icon(Icons.music_note_rounded,color:Colors.white,size:15),const SizedBox(width:4),Expanded(child:Text('يحتوي على: ${v.sound}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:13,shadows:shadow)))])]
  ]);
 }
}
