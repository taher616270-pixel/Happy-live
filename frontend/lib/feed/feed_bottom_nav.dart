import 'package:flutter/material.dart';
import 'feed_icons.dart';
class FeedBottomNav extends StatelessWidget {
 final int current; final ValueChanged<int>? onTap; final String friendsAvatar; final int friendsBadge,inboxBadge;
 const FeedBottomNav({super.key,this.current=0,this.onTap,this.friendsAvatar='',this.friendsBadge=4,this.inboxBadge=99});
 @override Widget build(BuildContext context){
  Widget badge(String t)=>Container(constraints:const BoxConstraints(minWidth:18),height:18,padding:const EdgeInsets.symmetric(horizontal:5),alignment:Alignment.center,decoration:BoxDecoration(color:kFeedRed,borderRadius:BorderRadius.circular(9)),child:Text(t,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w700,height:1)));
  Widget tab(int i,Widget icon,String label,{Widget? badgeW})=>Expanded(child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:()=>onTap?.call(i),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Stack(clipBehavior:Clip.none,children:[icon,if(badgeW!=null)Positioned(top:-6,left:-10,child:badgeW)]),const SizedBox(height:3),Text(label,style:TextStyle(color:Colors.white,fontSize:11,fontWeight:current==i?FontWeight.w700:FontWeight.w400))])));
  return Container(height:56+MediaQuery.of(context).padding.bottom,padding:EdgeInsets.only(bottom:MediaQuery.of(context).padding.bottom),color:Colors.black,child:Directionality(textDirection:TextDirection.rtl,child:Row(children:[
   tab(0,const Icon(Icons.home_rounded,color:Colors.white,size:27),'الصفحة الرئيسية'),
   tab(1,Container(width:27,height:27,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFF3A3A3C)),child:ClipOval(child:friendsAvatar.isEmpty?const Icon(Icons.person,color:Colors.white54,size:18):Image.network(friendsAvatar,fit:BoxFit.cover))),'الأصدقاء',badgeW:friendsBadge>0?badge('$friendsBadge'):null),
   Expanded(child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:()=>onTap?.call(2),child:const Center(child:PlusButton()))),
   tab(3,const Icon(Icons.chat_bubble_outline_rounded,color:Colors.white,size:26),'صندوق الوارد',badgeW:inboxBadge>0?badge(inboxBadge>99?'99+':'$inboxBadge'):null),
   tab(4,const Icon(Icons.person_outline_rounded,color:Colors.white,size:28),'الملف الشخصي')
  ])));
 }
}
