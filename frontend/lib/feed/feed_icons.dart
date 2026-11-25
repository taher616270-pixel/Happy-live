import 'package:flutter/material.dart';
const kFeedRed=Color(0xFFFE2C55), kFeedYellow=Color(0xFFFFC107), kFeedCyan=Color(0xFF20D5EC);
class CommentDotsIcon extends StatelessWidget {
 final double size; final Color color;
 const CommentDotsIcon({super.key,this.size=36,this.color=Colors.white});
 @override Widget build(BuildContext context)=>SizedBox(width:size,height:size,child:CustomPaint(painter:_CommentPainter(color)));
}
class _CommentPainter extends CustomPainter {
 final Color color; _CommentPainter(this.color);
 @override void paint(Canvas canvas,Size s){
  final w=s.width,h=s.height; final p=Path()..addRRect(RRect.fromLTRBR(w*.04,h*.06,w*.96,h*.80,Radius.circular(w*.38)))..moveTo(w*.62,h*.76)..lineTo(w*.84,h*.97)..lineTo(w*.80,h*.70)..close();
  canvas.drawShadow(p,Colors.black,3,false); canvas.drawPath(p,Paint()..color=color);
  final dot=Paint()..color=const Color(0xFF3A3A3C); for(final x in [.30,.50,.70]){canvas.drawCircle(Offset(w*x,h*.43),w*.055,dot);}
 }
 @override bool shouldRepaint(covariant _CommentPainter old)=>old.color!=color;
}
class LiveIcon extends StatelessWidget {
 const LiveIcon({super.key});
 @override Widget build(BuildContext context)=>SizedBox(width:30,height:26,child:Stack(alignment:Alignment.bottomCenter,children:[
  CustomPaint(size:const Size(30,8),painter:_AntennaPainter()),
  Container(width:30,height:20,alignment:Alignment.center,decoration:BoxDecoration(border:Border.all(color:Colors.white,width:2),borderRadius:BorderRadius.circular(5)),child:const Text('LIVE',style:TextStyle(color:Colors.white,fontSize:8.5,fontWeight:FontWeight.w900,height:1)))
 ]));
}
class _AntennaPainter extends CustomPainter {
 @override void paint(Canvas c,Size s){final p=Paint()..color=Colors.white..strokeWidth=2..strokeCap=StrokeCap.round;c.drawLine(Offset(s.width*.5,s.height),Offset(s.width*.28,0),p);c.drawLine(Offset(s.width*.5,s.height),Offset(s.width*.72,0),p);}
 @override bool shouldRepaint(covariant CustomPainter old)=>false;
}
class PlusButton extends StatelessWidget {
 const PlusButton({super.key});
 @override Widget build(BuildContext context)=>SizedBox(width:48,height:32,child:Stack(children:[
  Positioned(left:0,child:Container(width:40,height:32,decoration:BoxDecoration(color:kFeedCyan,borderRadius:BorderRadius.circular(9)))),
  Positioned(right:0,child:Container(width:40,height:32,decoration:BoxDecoration(color:kFeedRed,borderRadius:BorderRadius.circular(9)))),
  Center(child:Container(width:40,height:32,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(9)),child:const Icon(Icons.add_rounded,color:Colors.black,size:24)))
 ]));
}
class SpinDisc extends StatefulWidget {
 final String imageUrl; const SpinDisc({super.key,this.imageUrl=''});
 @override State<SpinDisc> createState()=>_SpinDiscState();
}
class _SpinDiscState extends State<SpinDisc> with SingleTickerProviderStateMixin {
 late final AnimationController _c=AnimationController(vsync:this,duration:const Duration(seconds:6))..repeat();
 @override void dispose(){_c.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>RotationTransition(turns:_c,child:Container(width:42,height:42,padding:const EdgeInsets.all(9),decoration:const BoxDecoration(shape:BoxShape.circle,gradient:LinearGradient(colors:[Color(0xFF2B2B2E),Color(0xFF0E0E10)])),child:ClipOval(child:widget.imageUrl.isEmpty?Container(color:const Color(0xFF3A3A3C),child:const Icon(Icons.music_note_rounded,color:Colors.white70,size:14)):Image.network(widget.imageUrl,fit:BoxFit.cover))));
}
