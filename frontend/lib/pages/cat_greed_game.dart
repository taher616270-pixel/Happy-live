import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _wheelApi = 'https://happy-live-api.taher616270.workers.dev/api/v1';
const _chips = [10, 500, 6000, 30000, 100000];

Future<void> showCatGreedGame(BuildContext context, {required String accessToken}) {
  return showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => SizedBox(height: MediaQuery.of(context).size.height * .94,
      child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: CatGreedGame(accessToken: accessToken))),
  );
}

class CatGreedGame extends StatefulWidget {
  const CatGreedGame({super.key, required this.accessToken});
  final String accessToken;
  @override State<CatGreedGame> createState() => _CatGreedGameState();
}

class _CatGreedGameState extends State<CatGreedGame> {
  Timer? _poll;
  Map<String, dynamic>? _state;
  String? _error, _notice;
  int _chip = 500, _hit = -1;
  bool _busy = false, _spinning = false, _refreshing = false;
  String _animatedRound = '';
  String _pendingBetKey = '', _pendingBetSignature = '';

  @override void initState() { super.initState(); _refresh(); _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _refresh()); }
  @override void dispose() { _poll?.cancel(); super.dispose(); }

  Map<String, String> get _headers => {'Content-Type':'application/json','Authorization':'Bearer ${widget.accessToken}'};

  String get _apiBase {
    if(!kIsWeb||Uri.base.host=='happy-live.pages.dev')return _wheelApi;
    final raw=Uri.base.queryParameters['catGreedApi']??'';
    final uri=Uri.tryParse(raw);
    final host=uri?.host??'';
    final valid=uri!=null&&uri.scheme=='https'&&uri.port==443&&uri.userInfo.isEmpty&&
      host!='happy-live-api.taher616270.workers.dev'&&
      RegExp(r'^[a-z0-9-]*happy-live-api[a-z0-9-]*\.taher616270\.workers\.dev
    final decoded = jsonDecode(response.body);
    if(decoded is! Map<String,dynamic>) throw Exception('استجابة الخادم غير صالحة');
    if(response.statusCode<200 || response.statusCode>=300) {
      final code=decoded['error']?.toString();
      final message=decoded['message']??(code=='state_rate_limited'?'طلبات التحديث كثيرة؛ انتظر قليلاً.':code=='bet_rate_limited'?'تجاوزت حد الرهانات السريع؛ انتظر قليلاً.':code??'تعذر تنفيذ الطلب');
      throw Exception(message);
    }
    return decoded;
  }

  Future<void> _refresh() async {
    if(_refreshing)return;
    _refreshing=true;
    try {
      final next=await _request('/games/cat-greed/state');
      if(!mounted)return;
      if(next['enabled']!=true&&next['roundId']==null){setState(()=>_error='اللعبة غير متاحة حالياً');return;}
      final round='${next['roundId']}';
      setState((){_state=next;_error=null;});
      if(next['phase']=='result' && round!=_animatedRound){_animatedRound=round;await _spin(next);}
    } catch(e) { if(mounted)setState(()=>_error=e.toString().replaceFirst('Exception: ','')); }
    finally { _refreshing=false; }
  }

  Future<void> _spin(Map<String,dynamic> s) async {
    if(_spinning)return;
    _spinning=true;
    final special=s['special']?.toString();
    final symbols=(s['symbols'] as List?)??const [];
    final targets=special=='salad'
      ? [for(var i=0;i<symbols.length;i++) if((symbols[i] as Map)['isVegetable']==true)i]
      : special=='pizza'
        ? [for(var i=0;i<symbols.length;i++) if((symbols[i] as Map)['isVegetable']!=true)i]
        : [s['resultSlot'] is int?s['resultSlot'] as int:math.Random().nextInt(8)];
    final activeTargets=targets.isEmpty?[0]:targets;
    final steps=special=='salad'||special=='pizza'?activeTargets.length*3:25;
    for(var k=0;k<steps;k++){
      if(!mounted){_spinning=false;return;}
      setState(()=>_hit=activeTargets[k%activeTargets.length]);
      await Future.delayed(Duration(milliseconds:55+(k*k*.32).round()));
    }
    if(!mounted)return;
    setState(()=>_hit=-1);
    _spinning=false;
    _message(s['special']=='salad'?'النتيجة: السلطة 🥗':s['special']=='pizza'?'النتيجة: البيتزا 🍕':'النتيجة: الرمز ${activeTargets.last+1}');
  }

  Future<void> _bet(int slot) async {
    final s=_state;
    if(s==null||s['enabled']!=true){_message('اللعبة متوقفة حالياً');return;}
    if(s['phase']!='betting'){_message('انتهى وقت الرهان');return;}
    if(_busy||(s['balance'] as num? ?? 0)<_chip){_message('الرصيد غير كافٍ أو يوجد طلب جارٍ');return;}
    final signature='${s['roundId']}:$slot:$_chip';
    if(_pendingBetSignature!=signature){
      final random=math.Random.secure();
      final bytes=List<int>.generate(16,(_)=>random.nextInt(256));
      bytes[6]=(bytes[6]&0x0f)|0x40;
      bytes[8]=(bytes[8]&0x3f)|0x80;
      final hex=bytes.map((value)=>value.toRadixString(16).padLeft(2,'0')).join();
      _pendingBetKey='${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
      _pendingBetSignature=signature;
    }
    setState(()=>_busy=true);
    try{
      final next=await _request('/games/cat-greed/bet',method:'POST',body:{'roundId':s['roundId'],'slot':slot,'amount':_chip,'idempotencyKey':_pendingBetKey});
      _pendingBetKey='';_pendingBetSignature='';
      if(mounted)setState(()=>_state=next);
    }catch(e){_message(e.toString().replaceFirst('Exception: ',''));await _refresh();}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  void _message(String value){
    setState(()=>_notice=value);
    Future.delayed(const Duration(seconds:3),(){if(mounted&&_notice==value)setState(()=>_notice=null);});
  }
  String _fmt(dynamic value){
    final n=(value as num? ?? 0).toInt();
    if(n>=1000000)return '${(n/1000000).toStringAsFixed(2)}M';
    if(n>=1000)return '${(n/1000).toStringAsFixed(1)}K';
    return '$n';
  }

  String _centerLabel(Map<String,dynamic> s){
    if(s['phase']!='result')return '${s['secondsLeft']}s';
    if(s['special']=='salad')return '🥗';
    if(s['special']=='pizza')return '🍕';
    final symbols=(s['symbols'] as List?)??const [];
    final index=s['resultSlot'] as int? ?? -1;
    if(index>=0&&index<symbols.length)return (symbols[index] as Map)['emoji']?.toString()??'🎡';
    return '🎡';
  }

  @override Widget build(BuildContext context){
    final s=_state;
    return Directionality(textDirection:TextDirection.rtl,child:Material(color:const Color(0xFF101019),
      child:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF101019),Color(0xFF24172A),Color(0xFF09080D)])),
        child:SafeArea(child:s==null
          ? Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
              const Text('🐱 قط الجشع',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w900)),
              const SizedBox(height:12),if(_error==null)const CircularProgressIndicator(color:Color(0xFFD4AF37)),
              if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.white70)),
              TextButton(onPressed:_refresh,child:const Text('إعادة المحاولة')),
            ]))
          : Column(children:[
              Padding(padding:const EdgeInsets.fromLTRB(14,10,14,8),child:Row(children:[
                const Text('🐱 قط الجشع',style:TextStyle(color:Color(0xFFFFD978),fontSize:20,fontWeight:FontWeight.w900)),
                const Spacer(),Text('🪙 ${_fmt(s['balance'])}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),
                IconButton(onPressed:()=>Navigator.of(context).maybePop(),icon:const Icon(Icons.close,color:Colors.white)),
              ])),
              Text('جولة ${s['roundId']} · ${s['enabled']!=true?'اللعبة متوقفة':s['phase']=='betting'?'استقبال الرهانات':'النتيجة'} · ${s['secondsLeft']} ث',style:const TextStyle(color:Colors.white70,fontWeight:FontWeight.bold)),
              if(s['enabled']!=true)const Padding(padding:EdgeInsets.all(4),child:Text('لا تُقبل رهانات جديدة؛ ستُعرض نتيجة الجولة الحالية وتُصرف جوائزها تلقائياً.',style:TextStyle(color:Color(0xFFFFD978),fontSize:11))),
              if(s['specialOdds'] is Map)Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text('السلطة ${(((s['specialOdds'] as Map)['saladWeightBp'] as num? ?? 0)/100).toStringAsFixed(2)}% · البيتزا ${(((s['specialOdds'] as Map)['pizzaWeightBp'] as num? ?? 0)/100).toStringAsFixed(2)}%',style:const TextStyle(color:Color(0xFFD4AF37),fontSize:10))),
              if(s['seedCommitment']!=null)Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:Text('بصمة نزاهة الجولة: ${s['seedCommitment'].toString().substring(0,s['seedCommitment'].toString().length<24?s['seedCommitment'].toString().length:24)}…',style:const TextStyle(color:Color(0xFFD4AF37),fontSize:10))),
              Expanded(child:LayoutBuilder(builder:(context,c){
                final d=c.maxWidth<c.maxHeight?c.maxWidth:c.maxHeight;
                return Center(child:SizedBox(width:d,height:d,child:Stack(children:[
                  for(var i=0;i<8;i++)Positioned(left:d/2+d*.34*math.sin(i*math.pi/4)-d*.135,top:d/2-d*.34*math.cos(i*math.pi/4)-d*.135,width:d*.27,height:d*.27,child:_slot(i,s,d*.27)),
                  Center(child:Container(width:d*.25,height:d*.25,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF8A4B2A),border:Border.all(color:const Color(0xFFD4AF37),width:4)),child:Center(child:Text(_centerLabel(s),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:22))))),
                ])));
              })),
              if(s['special']=='salad'||s['special']=='pizza')Text(s['special']=='salad'?'🥗 السلطة':'🍕 البيتزا',style:const TextStyle(color:Color(0xFFFFD978),fontSize:24,fontWeight:FontWeight.w900)),
              Text('رهاناتك: ${_fmt((s['myBets'] as List).fold<num>(0,(a,b)=>a+(b as num)))}',style:const TextStyle(color:Colors.white70)),
              if(_notice!=null)Padding(padding:const EdgeInsets.all(6),child:Text(_notice!,style:const TextStyle(color:Color(0xFFFFD978),fontWeight:FontWeight.bold))),
              Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Wrap(spacing:7,children:[
                for(final chip in _chips)ChoiceChip(label:Text(_fmt(chip)),selected:_chip==chip,selectedColor:const Color(0xFFD4AF37),onSelected:(_)=>setState(()=>_chip=chip)),
              ])),
              if(_error!=null)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(_error!,style:const TextStyle(color:Colors.redAccent))),
              const SizedBox(height:8),
            ]),
        ),
      ),
    ));
  }

  bool _safeImage(dynamic value){
    if(value==null)return false;
    final uri=Uri.tryParse(value.toString());
    return uri!=null&&uri.scheme=='https'&&(uri.host=='ik.imagekit.io'||uri.host.endsWith('.imagekit.io'))&&uri.userInfo.isEmpty&&uri.port==443;
  }

  Widget _slot(int i,Map<String,dynamic> s,double d){
    final symbols=(s['symbols'] as List?)??const [];
    final symbol=i<symbols.length?Map<String,dynamic>.from(symbols[i] as Map):<String,dynamic>{};
    final pools=(s['pools'] as List?)??const [],bets=(s['myBets'] as List?)??const [];
    final odds=(s['odds'] as List?)??const [];
    final currentOdds=i<odds.length?Map<String,dynamic>.from(odds[i] as Map):<String,dynamic>{};
    final poolValues=pools.map((e)=>(e as num).toDouble()).toList();
    final hot=poolValues.isNotEmpty&&poolValues[i]==poolValues.reduce((a,b)=>a>b?a:b);
    return GestureDetector(onTap:s['enabled']==true?()=>_bet(i):null,child:AnimatedContainer(duration:const Duration(milliseconds:120),
      transform:Matrix4.identity()..scale(_hit==i?1.1:1.0),
      decoration:BoxDecoration(shape:BoxShape.circle,color:_hit==i?const Color(0xFFFFE68A):const Color(0xFFFFF3C4),border:Border.all(color:const Color(0xFFB67A39),width:3),boxShadow:_hit==i?[const BoxShadow(color:Color(0xFFFFD700),blurRadius:18,spreadRadius:3)]:null),
      child:Stack(alignment:Alignment.center,children:[
        Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          _safeImage(symbol['imageUrl'])?Image.network(symbol['imageUrl'].toString(),width:d*.42,height:d*.42,fit:BoxFit.contain,errorBuilder:(_,__,___)=>Text(symbol['emoji']?.toString()??'🐱',style:TextStyle(fontSize:d*.35))):Text(symbol['emoji']?.toString()??'🐱',style:TextStyle(fontSize:d*.35)),
          Text('${symbol['multiplier']??1}x',style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.15,fontWeight:FontWeight.w900)),
          Text(_fmt(pools.isNotEmpty?pools[i]:0),style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.12)),
          Text('ظهور ${((currentOdds['appearanceProbabilityBp'] as num? ?? 0)/100).toStringAsFixed(1)}% · فوز ${((currentOdds['winProbabilityBp'] as num? ?? 0)/100).toStringAsFixed(1)}%',style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.075)),
          Text('عائد نظري ${((currentOdds['expectedReturnBp'] as num? ?? 0)/100).toStringAsFixed(1)}%',style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.085)),
          if(bets.isNotEmpty&&(bets[i] as num)>0)Text('رهانك ${_fmt(bets[i])}',style:TextStyle(color:const Color(0xFF7A22FF),fontSize:d*.09)),
        ]),
        if(hot)const Positioned(top:3,right:4,child:Text('HOT',style:TextStyle(color:Colors.red,fontSize:8,fontWeight:FontWeight.w900))),
      ]),
    ));
  }
}
,caseSensitive:false).hasMatch(host);
    return valid?uri.origin+'/api/v1':'';
  }

  Future<Map<String,dynamic>> _request(String path,{String method='GET',Map<String,dynamic>? body}) async {
    final apiBase=_apiBase;
    if(apiBase.isEmpty) {
      throw Exception('نسخة المعاينة غير موصولة بخادم اختبار معزول؛ تم تعطيل اللعبة لحماية رصيد الإنتاج.');
    }
    final uri=Uri.parse('$apiBase$path');
    final response = method == 'GET'
      ? await http.get(uri,headers:_headers)
      : await http.post(uri,headers:_headers,body:jsonEncode(body));
    final decoded = jsonDecode(response.body);
    if(decoded is! Map<String,dynamic>) throw Exception('استجابة الخادم غير صالحة');
    if(response.statusCode<200 || response.statusCode>=300) {
      final code=decoded['error']?.toString();
      final message=decoded['message']??(code=='state_rate_limited'?'طلبات التحديث كثيرة؛ انتظر قليلاً.':code=='bet_rate_limited'?'تجاوزت حد الرهانات السريع؛ انتظر قليلاً.':code??'تعذر تنفيذ الطلب');
      throw Exception(message);
    }
    return decoded;
  }

  Future<void> _refresh() async {
    if(_refreshing)return;
    _refreshing=true;
    try {
      final next=await _request('/games/cat-greed/state');
      if(!mounted)return;
      if(next['enabled']!=true&&next['roundId']==null){setState(()=>_error='اللعبة غير متاحة حالياً');return;}
      final round='${next['roundId']}';
      setState((){_state=next;_error=null;});
      if(next['phase']=='result' && round!=_animatedRound){_animatedRound=round;await _spin(next);}
    } catch(e) { if(mounted)setState(()=>_error=e.toString().replaceFirst('Exception: ','')); }
    finally { _refreshing=false; }
  }

  Future<void> _spin(Map<String,dynamic> s) async {
    if(_spinning)return;
    _spinning=true;
    final special=s['special']?.toString();
    final symbols=(s['symbols'] as List?)??const [];
    final targets=special=='salad'
      ? [for(var i=0;i<symbols.length;i++) if((symbols[i] as Map)['isVegetable']==true)i]
      : special=='pizza'
        ? [for(var i=0;i<symbols.length;i++) if((symbols[i] as Map)['isVegetable']!=true)i]
        : [s['resultSlot'] is int?s['resultSlot'] as int:math.Random().nextInt(8)];
    final activeTargets=targets.isEmpty?[0]:targets;
    final steps=special=='salad'||special=='pizza'?activeTargets.length*3:25;
    for(var k=0;k<steps;k++){
      if(!mounted){_spinning=false;return;}
      setState(()=>_hit=activeTargets[k%activeTargets.length]);
      await Future.delayed(Duration(milliseconds:55+(k*k*.32).round()));
    }
    if(!mounted)return;
    setState(()=>_hit=-1);
    _spinning=false;
    _message(s['special']=='salad'?'النتيجة: السلطة 🥗':s['special']=='pizza'?'النتيجة: البيتزا 🍕':'النتيجة: الرمز ${activeTargets.last+1}');
  }

  Future<void> _bet(int slot) async {
    final s=_state;
    if(s==null||s['enabled']!=true){_message('اللعبة متوقفة حالياً');return;}
    if(s['phase']!='betting'){_message('انتهى وقت الرهان');return;}
    if(_busy||(s['balance'] as num? ?? 0)<_chip){_message('الرصيد غير كافٍ أو يوجد طلب جارٍ');return;}
    final signature='${s['roundId']}:$slot:$_chip';
    if(_pendingBetSignature!=signature){
      final random=math.Random.secure();
      final bytes=List<int>.generate(16,(_)=>random.nextInt(256));
      bytes[6]=(bytes[6]&0x0f)|0x40;
      bytes[8]=(bytes[8]&0x3f)|0x80;
      final hex=bytes.map((value)=>value.toRadixString(16).padLeft(2,'0')).join();
      _pendingBetKey='${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
      _pendingBetSignature=signature;
    }
    setState(()=>_busy=true);
    try{
      final next=await _request('/games/cat-greed/bet',method:'POST',body:{'roundId':s['roundId'],'slot':slot,'amount':_chip,'idempotencyKey':_pendingBetKey});
      _pendingBetKey='';_pendingBetSignature='';
      if(mounted)setState(()=>_state=next);
    }catch(e){_message(e.toString().replaceFirst('Exception: ',''));await _refresh();}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  void _message(String value){
    setState(()=>_notice=value);
    Future.delayed(const Duration(seconds:3),(){if(mounted&&_notice==value)setState(()=>_notice=null);});
  }
  String _fmt(dynamic value){
    final n=(value as num? ?? 0).toInt();
    if(n>=1000000)return '${(n/1000000).toStringAsFixed(2)}M';
    if(n>=1000)return '${(n/1000).toStringAsFixed(1)}K';
    return '$n';
  }

  String _centerLabel(Map<String,dynamic> s){
    if(s['phase']!='result')return '${s['secondsLeft']}s';
    if(s['special']=='salad')return '🥗';
    if(s['special']=='pizza')return '🍕';
    final symbols=(s['symbols'] as List?)??const [];
    final index=s['resultSlot'] as int? ?? -1;
    if(index>=0&&index<symbols.length)return (symbols[index] as Map)['emoji']?.toString()??'🎡';
    return '🎡';
  }

  @override Widget build(BuildContext context){
    final s=_state;
    return Directionality(textDirection:TextDirection.rtl,child:Material(color:const Color(0xFF101019),
      child:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF101019),Color(0xFF24172A),Color(0xFF09080D)])),
        child:SafeArea(child:s==null
          ? Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
              const Text('🐱 قط الجشع',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w900)),
              const SizedBox(height:12),if(_error==null)const CircularProgressIndicator(color:Color(0xFFD4AF37)),
              if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.white70)),
              TextButton(onPressed:_refresh,child:const Text('إعادة المحاولة')),
            ]))
          : Column(children:[
              Padding(padding:const EdgeInsets.fromLTRB(14,10,14,8),child:Row(children:[
                const Text('🐱 قط الجشع',style:TextStyle(color:Color(0xFFFFD978),fontSize:20,fontWeight:FontWeight.w900)),
                const Spacer(),Text('🪙 ${_fmt(s['balance'])}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),
                IconButton(onPressed:()=>Navigator.of(context).maybePop(),icon:const Icon(Icons.close,color:Colors.white)),
              ])),
              Text('جولة ${s['roundId']} · ${s['enabled']!=true?'اللعبة متوقفة':s['phase']=='betting'?'استقبال الرهانات':'النتيجة'} · ${s['secondsLeft']} ث',style:const TextStyle(color:Colors.white70,fontWeight:FontWeight.bold)),
              if(s['enabled']!=true)const Padding(padding:EdgeInsets.all(4),child:Text('لا تُقبل رهانات جديدة؛ ستُعرض نتيجة الجولة الحالية وتُصرف جوائزها تلقائياً.',style:TextStyle(color:Color(0xFFFFD978),fontSize:11))),
              if(s['specialOdds'] is Map)Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text('السلطة ${(((s['specialOdds'] as Map)['saladWeightBp'] as num? ?? 0)/100).toStringAsFixed(2)}% · البيتزا ${(((s['specialOdds'] as Map)['pizzaWeightBp'] as num? ?? 0)/100).toStringAsFixed(2)}%',style:const TextStyle(color:Color(0xFFD4AF37),fontSize:10))),
              if(s['seedCommitment']!=null)Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:Text('بصمة نزاهة الجولة: ${s['seedCommitment'].toString().substring(0,s['seedCommitment'].toString().length<24?s['seedCommitment'].toString().length:24)}…',style:const TextStyle(color:Color(0xFFD4AF37),fontSize:10))),
              Expanded(child:LayoutBuilder(builder:(context,c){
                final d=c.maxWidth<c.maxHeight?c.maxWidth:c.maxHeight;
                return Center(child:SizedBox(width:d,height:d,child:Stack(children:[
                  for(var i=0;i<8;i++)Positioned(left:d/2+d*.34*math.sin(i*math.pi/4)-d*.135,top:d/2-d*.34*math.cos(i*math.pi/4)-d*.135,width:d*.27,height:d*.27,child:_slot(i,s,d*.27)),
                  Center(child:Container(width:d*.25,height:d*.25,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF8A4B2A),border:Border.all(color:const Color(0xFFD4AF37),width:4)),child:Center(child:Text(_centerLabel(s),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:22))))),
                ])));
              })),
              if(s['special']=='salad'||s['special']=='pizza')Text(s['special']=='salad'?'🥗 السلطة':'🍕 البيتزا',style:const TextStyle(color:Color(0xFFFFD978),fontSize:24,fontWeight:FontWeight.w900)),
              Text('رهاناتك: ${_fmt((s['myBets'] as List).fold<num>(0,(a,b)=>a+(b as num)))}',style:const TextStyle(color:Colors.white70)),
              if(_notice!=null)Padding(padding:const EdgeInsets.all(6),child:Text(_notice!,style:const TextStyle(color:Color(0xFFFFD978),fontWeight:FontWeight.bold))),
              Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Wrap(spacing:7,children:[
                for(final chip in _chips)ChoiceChip(label:Text(_fmt(chip)),selected:_chip==chip,selectedColor:const Color(0xFFD4AF37),onSelected:(_)=>setState(()=>_chip=chip)),
              ])),
              if(_error!=null)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(_error!,style:const TextStyle(color:Colors.redAccent))),
              const SizedBox(height:8),
            ]),
        ),
      ),
    ));
  }

  bool _safeImage(dynamic value){
    if(value==null)return false;
    final uri=Uri.tryParse(value.toString());
    return uri!=null&&uri.scheme=='https'&&(uri.host=='ik.imagekit.io'||uri.host.endsWith('.imagekit.io'))&&uri.userInfo.isEmpty&&uri.port==443;
  }

  Widget _slot(int i,Map<String,dynamic> s,double d){
    final symbols=(s['symbols'] as List?)??const [];
    final symbol=i<symbols.length?Map<String,dynamic>.from(symbols[i] as Map):<String,dynamic>{};
    final pools=(s['pools'] as List?)??const [],bets=(s['myBets'] as List?)??const [];
    final odds=(s['odds'] as List?)??const [];
    final currentOdds=i<odds.length?Map<String,dynamic>.from(odds[i] as Map):<String,dynamic>{};
    final poolValues=pools.map((e)=>(e as num).toDouble()).toList();
    final hot=poolValues.isNotEmpty&&poolValues[i]==poolValues.reduce((a,b)=>a>b?a:b);
    return GestureDetector(onTap:s['enabled']==true?()=>_bet(i):null,child:AnimatedContainer(duration:const Duration(milliseconds:120),
      transform:Matrix4.identity()..scale(_hit==i?1.1:1.0),
      decoration:BoxDecoration(shape:BoxShape.circle,color:_hit==i?const Color(0xFFFFE68A):const Color(0xFFFFF3C4),border:Border.all(color:const Color(0xFFB67A39),width:3),boxShadow:_hit==i?[const BoxShadow(color:Color(0xFFFFD700),blurRadius:18,spreadRadius:3)]:null),
      child:Stack(alignment:Alignment.center,children:[
        Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          _safeImage(symbol['imageUrl'])?Image.network(symbol['imageUrl'].toString(),width:d*.42,height:d*.42,fit:BoxFit.contain,errorBuilder:(_,__,___)=>Text(symbol['emoji']?.toString()??'🐱',style:TextStyle(fontSize:d*.35))):Text(symbol['emoji']?.toString()??'🐱',style:TextStyle(fontSize:d*.35)),
          Text('${symbol['multiplier']??1}x',style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.15,fontWeight:FontWeight.w900)),
          Text(_fmt(pools.isNotEmpty?pools[i]:0),style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.12)),
          Text('ظهور ${((currentOdds['appearanceProbabilityBp'] as num? ?? 0)/100).toStringAsFixed(1)}% · فوز ${((currentOdds['winProbabilityBp'] as num? ?? 0)/100).toStringAsFixed(1)}%',style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.075)),
          Text('عائد نظري ${((currentOdds['expectedReturnBp'] as num? ?? 0)/100).toStringAsFixed(1)}%',style:TextStyle(color:const Color(0xFF5A3A00),fontSize:d*.085)),
          if(bets.isNotEmpty&&(bets[i] as num)>0)Text('رهانك ${_fmt(bets[i])}',style:TextStyle(color:const Color(0xFF7A22FF),fontSize:d*.09)),
        ]),
        if(hot)const Positioned(top:3,right:4,child:Text('HOT',style:TextStyle(color:Colors.red,fontSize:8,fontWeight:FontWeight.w900))),
      ]),
    ));
  }
}
