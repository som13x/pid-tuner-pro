import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/robust_tune.dart';
import 'package:pid_tuner_pro_core/stability_analysis.dart';
import 'package:pid_tuner_pro_core/stability_studio.dart';

// Pure top-level function so the CPU-heavy search can run in an isolate.
Map<String,dynamic> _analyze(Map<String,dynamic> input) {
  final plants = (input['plants'] as List).cast<Map<String,dynamic>>();
  final observations = <PlantObservation>[];
  for (var i=0;i<plants.length;i++) {
    final p=plants[i];
    observations.add(PlantObservation(Plant(
      gain:(p['k'] as num).toDouble(),
      tau:(p['t'] as num).toDouble(),
      delay:(p['l'] as num).toDouble()),
      label:'Step ${i+1}',rSquared:.99,normalizedRmse:.02));
  }
  // In this demo the quality fields are placeholders. Real Step Test results
  // must supply actual fit-quality values before they are accepted.
  final ensemble=ModelEnsemble.build(observations);
  final limits=StabilityLimits(
    minimumPhaseMarginDegrees:(input['pm'] as num).toDouble(),
    minimumGainMarginDb:(input['gm'] as num).toDouble());
  final studio=StabilityStudio(ensemble,limits:limits);
  final report=studio.run(shortlist:20);
  Map<String,dynamic> candidate(StabilityCandidateReport c) => {
    'pb':c.pb,'ti':c.ti,'feasible':c.feasible,
    'timeDomainFeasible':c.timeDomainFeasible,
    'frequencyDomainFeasible':c.frequencyDomainFeasible,
    'worstIae':c.worstIae,'worstTravel':c.worstTravel,
    'worstError':c.worstError,
    'worstPhaseMargin':c.margins.worstPhaseMarginDegrees,
    'worstGainMargin':c.margins.worstGainMarginDb,
    'violations':c.violations,
    'scenarioMargins':c.margins.scenarios.map((m)=>{
      'phaseMargin':m.phaseMarginDegrees,'gainMargin':m.gainMarginDb,
      'gainCrossover':m.gainCrossoverRadSec,'passes':m.passes,
    }).toList(),
  };
  final candidates=report.candidates.map(candidate).toList();
  final bode=<String,List<Map<String,double>>>{};
  for (final c in [report.baseline,...report.candidates]) {
    final key='${c.pb.toStringAsFixed(7)}:${c.ti.toStringAsFixed(7)}';
    if(bode.containsKey(key)) continue;
    bode[key]=studio.bode(ensemble.nominal,c.pb,c.ti,count:160)
      .map((p)=>{'omega':p.omega,'db':p.magnitudeDb,
        'phase':p.phaseDegrees}).toList();
  }
  return {'baseline':candidate(report.baseline),'candidates':candidates,
    'scenarioCount':report.scenarioCount,'evaluated':report.evaluated,
    'limits':{'pm':limits.minimumPhaseMarginDegrees,
      'gm':limits.minimumGainMarginDb},'bode':bode,
    'modelSource':'DEMONSTRATION_INPUT_NOT_VALIDATED'};
}

class StabilityScreen extends StatefulWidget {
  const StabilityScreen({super.key, this.initialModel});
  final Map<String, double>? initialModel;
  @override State<StabilityScreen> createState()=>_StabilityScreenState();
}

class _StabilityScreenState extends State<StabilityScreen> {
  final inputs = [
    [TextEditingController(text:'0.7'),TextEditingController(text:'10'),TextEditingController(text:'2')],
    [TextEditingController(text:'0.9'),TextEditingController(text:'16'),TextEditingController(text:'5')],
  ];
  @override void initState() {
    super.initState();
    final m = widget.initialModel;
    if (m != null) {
      for (var i = 0; i < 3; i++) {
        inputs[0][i].text = [m['K']!, m['T']!, m['L']!][i].toString();
      }
      // Remove the demonstration second model: never mix it with measured data.
      final demo = inputs.removeLast();
      for (final c in demo) { c.dispose(); }
    }
  }
  double pm=45,gm=6;
  bool busy=false;
  String? error;
  Map<String,dynamic>? report;
  int selected=-1;
  @override void dispose(){for(final row in inputs){for(final c in row){c.dispose();}}super.dispose();}
  Future<void> run() async {
    setState(() {busy=true;error=null;report=null;});
    try {
      final plants=inputs.map((r)=>{'k':double.parse(r[0].text.replaceAll(',','.')),
        't':double.parse(r[1].text.replaceAll(',','.')),
        'l':double.parse(r[2].text.replaceAll(',','.'))}).toList();
      final result=await compute(_analyze,{'plants':plants,'pm':pm,'gm':gm});
      if(mounted)setState((){report=result;selected=-1;});
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final candidates=(report?['candidates'] as List?)??[];
    final baseline=report?['baseline'] as Map<String,dynamic>?;
    final chosen=selected<0?baseline:(selected<candidates.length?
      candidates[selected] as Map<String,dynamic>:baseline);
    final key=chosen==null?'':'${(chosen['pb'] as num).toStringAsFixed(7)}:${(chosen['ti'] as num).toStringAsFixed(7)}';
    final bode=report==null?null:(report!['bode'] as Map)[key] as List?;
    return Scaffold(appBar:AppBar(title:const Text('Stability Analysis')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('Robust PI + FOPDT',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Text(widget.initialModel == null ? 'Демонстрационные K/T/L.' : 'Модель из выбранной карточки контура. Проверяйте применимость к рабочей точке.'),
        const SizedBox(height:12),
        ...List.generate(inputs.length,(i)=>Card(child:Padding(
          padding:const EdgeInsets.all(12),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Модель ${i+1}',style:const TextStyle(fontWeight:FontWeight.bold)),
            Row(children:List.generate(3,(j)=>Expanded(child:Padding(
              padding:const EdgeInsets.only(right:8),child:TextField(
                controller:inputs[i][j],keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true),
                decoration:InputDecoration(labelText:['K','T, с','L, с'][j])))))),
          ])))),
        Text('Минимальный запас по фазе: ${pm.toStringAsFixed(0)}°'),
        Slider(value:pm,min:20,max:80,divisions:12,onChanged:(v)=>setState(()=>pm=v)),
        Text('Минимальный запас по усилению: ${gm.toStringAsFixed(0)} дБ'),
        Slider(value:gm,min:3,max:15,divisions:12,onChanged:(v)=>setState(()=>gm=v)),
        FilledButton.icon(onPressed:busy?null:run,
          icon:busy?const SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.analytics),
          label:Text(busy?'Расчёт…':'Проверить устойчивость')),
        if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
        if(report!=null)...[
          const SizedBox(height:12),
          Text('Проверено настроек: ${report!['evaluated']} · сценариев: ${report!['scenarioCount']}'),
          const Text('Результаты отсортированы по активности клапана. Частотные ограничения проверены после поиска.'),
          RadioListTile<int>(value:-1,groupValue:selected,onChanged:(v)=>setState(()=>selected=v!),
            title:const Text('Исходная PB 120% · Ti 20 с'),
            subtitle:Text(baseline?['feasible']==true?'Допустима':'Не прошла все проверки')),
          ...List.generate(candidates.length,(i){
            final c=candidates[i] as Map<String,dynamic>;
            return RadioListTile<int>(value:i,groupValue:selected,
              onChanged:(v)=>setState(()=>selected=v!),
              title:Text('PB ${(c['pb'] as num).toStringAsFixed(1)}% · Ti ${(c['ti'] as num).toStringAsFixed(1)} с'),
              subtitle:Text('${c['feasible']==true?'Допустима':'Отклонена'} · '
                'MV ход ${(c['worstTravel'] as num).toStringAsFixed(1)}% · '
                'PM ${(c['worstPhaseMargin'] as num).toStringAsFixed(1)}°'));
          }),
          if(chosen!=null)...[
            const Divider(),
            Text('Худший запас по фазе: ${(chosen['worstPhaseMargin'] as num).toStringAsFixed(2)}°'),
            Text('Худший запас по усилению: ${chosen['worstGainMargin']==null?'∞ (нет конечного пересечения)':(chosen['worstGainMargin'] as num).toStringAsFixed(2)} дБ'),
            Text('Макс. ошибка PV: ${(chosen['worstError'] as num).toStringAsFixed(2)}% шкалы'),
            Text('Суммарный ход MV: ${(chosen['worstTravel'] as num).toStringAsFixed(2)}%'),
            if((chosen['violations'] as List).isNotEmpty)
              ...((chosen['violations'] as List).map((v)=>Text('• $v',style:const TextStyle(color:Colors.deepOrange)))),
            const SizedBox(height:12),
            const Text('Диаграмма Боде · модуль, дБ'),
            SizedBox(height:190,child:_BodePlot(points:bode,field:'db')),
            const SizedBox(height:12),
            const Text('Диаграмма Боде · фаза, ° (развёрнутая)'),
            SizedBox(height:190,child:_BodePlot(points:bode,field:'phase')),
            const SizedBox(height:12),
            const Text('Запасы по сценариям',style:TextStyle(fontWeight:FontWeight.bold)),
            ...List.generate((chosen['scenarioMargins'] as List).length,(i){
              final s=(chosen['scenarioMargins'] as List)[i] as Map;
              return ListTile(dense:true,title:Text('Сценарий ${i+1}'),
                subtitle:Text('PM ${(s['phaseMargin'] as num).toStringAsFixed(1)}° · '
                  'GM ${s['gainMargin']==null?'∞':(s['gainMargin'] as num).toStringAsFixed(1)} дБ'),
                trailing:Icon(s['passes']==true?Icons.check_circle:Icons.warning_amber,
                  color:s['passes']==true?Colors.teal:Colors.deepOrange));
            }),
          ],
          ExpansionTile(title:const Text('JSON-отчёт'),children:[
            SelectableText(const JsonEncoder.withIndent('  ').convert(report)),
          ]),
        ],
      ]));
  }
}

class _BodePlot extends StatelessWidget {
  final List? points;
  final String field;
  const _BodePlot({required this.points,required this.field});
  @override Widget build(BuildContext context)=>CustomPaint(
    painter:_BodePainter(points,field),child:const SizedBox.expand());
}
class _BodePainter extends CustomPainter {
  final List? points;
  final String field;
  _BodePainter(this.points,this.field);
  @override void paint(Canvas canvas,Size size){
    if(points==null||points!.length<2)return;
    final p=points!.cast<Map<String,double>>();
    const left=46.0,right=12.0,top=10.0,bottom=25.0;
    final w=math.max(1.0,size.width-left-right),h=math.max(1.0,size.height-top-bottom);
    final minX=math.log(p.first['omega']!),maxX=math.log(p.last['omega']!);
    final minY=p.map((x)=>x[field]!).reduce(math.min);
    final maxY=p.map((x)=>x[field]!).reduce(math.max);
    final spanY=math.max(1.0,maxY-minY);
    Offset xy(Map<String,double> point)=>Offset(
      left+(math.log(point['omega']!)-minX)/(maxX-minX)*w,
      top+h-(point[field]!-minY)/spanY*h);
    final axis=Paint()..color=Colors.grey..strokeWidth=1;
    canvas.drawLine(const Offset(left,top),Offset(left,top+h),axis);
    canvas.drawLine(Offset(left,top+h),Offset(left+w,top+h),axis);
    final path=Path()..moveTo(xy(p.first).dx,xy(p.first).dy);
    for(final point in p.skip(1)){final o=xy(point);path.lineTo(o.dx,o.dy);}
    canvas.drawPath(path,Paint()..color=Colors.teal..strokeWidth=2..style=PaintingStyle.stroke);
    void label(String s,Offset at){final tp=TextPainter(text:TextSpan(text:s,
      style:const TextStyle(fontSize:10,color:Colors.black87)),
      textDirection:TextDirection.ltr)..layout();tp.paint(canvas,at);}
    label(maxY.toStringAsFixed(1),const Offset(0,top));
    label(minY.toStringAsFixed(1),Offset(0,top+h-12));
    label('${p.first['omega']!.toStringAsExponential(0)} рад/с',Offset(left,top+h+5));
    label('${p.last['omega']!.toStringAsExponential(0)}',Offset(left+w-30,top+h+5));
  }
  @override bool shouldRepaint(covariant _BodePainter old)=>true;
}
