import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nearby/nearby.dart';

void main() => runApp(const SwarmApp());

class SwarmApp extends StatelessWidget {
  const SwarmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SWARM Mobile Agent',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const AgentPage(),
  );
}

class Point2 {
  final double x, y;
  const Point2(this.x, this.y);
  Map<String, dynamic> json() => {'x': x, 'y': y};
  factory Point2.fromJson(Map<String, dynamic> j) =>
      Point2((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
  double d2(Point2 p) => pow(x-p.x, 2).toDouble() + pow(y-p.y, 2).toDouble();
}

class Proposal {
  final int agent;
  final List<Point2> centres;
  final List<int> sizes;
  final double sse;
  Proposal(this.agent, this.centres, this.sizes, this.sse);
  double get variance {
    final mean = sizes.reduce((a,b)=>a+b) / sizes.length;
    return sizes.map((n)=>pow(n-mean,2).toDouble()).reduce((a,b)=>a+b) / sizes.length;
  }
  Map<String,dynamic> toJson() => {
    'type':'proposal', 'agent':agent, 'centres':centres.map((p)=>p.json()).toList(),
    'sizes':sizes, 'sse':sse
  };
  factory Proposal.fromJson(Map<String,dynamic> j) => Proposal(
    j['agent'] as int,
    (j['centres'] as List).map((e)=>Point2.fromJson(Map<String,dynamic>.from(e))).toList(),
    (j['sizes'] as List).map((e)=>e as int).toList(),
    (j['sse'] as num).toDouble()
  );
}

class KResult {
  final List<Point2> centres;
  final List<int> sizes;
  final double sse;
  KResult(this.centres,this.sizes,this.sse);
}

KResult kmeans(List<Point2> pts, int seed) {
  const k=3;
  if (pts.length<k) throw Exception('O CSV necessita de pelo menos 3 pontos.');
  final idx=List<int>.generate(pts.length,(i)=>i)..shuffle(Random(seed));
  var centres=idx.take(k).map((i)=>pts[i]).toList();
  var labels=List<int>.filled(pts.length,-1);
  for(var it=0;it<300;it++) {
    var changed=false;
    for(var i=0;i<pts.length;i++) {
      var best=0, bestD=pts[i].d2(centres[0]);
      for(var c=1;c<k;c++) {
        final d=pts[i].d2(centres[c]);
        if(d<bestD){best=c;bestD=d;}
      }
      if(labels[i]!=best){labels[i]=best;changed=true;}
    }
    final sx=List<double>.filled(k,0), sy=List<double>.filled(k,0);
    final n=List<int>.filled(k,0);
    for(var i=0;i<pts.length;i++){final c=labels[i];sx[c]+=pts[i].x;sy[c]+=pts[i].y;n[c]++;}
    final next=<Point2>[];
    for(var c=0;c<k;c++){
      next.add(n[c]==0 ? centres[c] : Point2(sx[c]/n[c],sy[c]/n[c]));
    }
    var shift=0.0;
    for(var c=0;c<k;c++){shift=max(shift,sqrt(next[c].d2(centres[c])));}
    centres=next;
    if(!changed || shift<1e-7) break;
  }
  final sizes=List<int>.filled(k,0);
  var sse=0.0;
  for(final p in pts){
    var best=0, d=p.d2(centres[0]);
    for(var c=1;c<k;c++){final q=p.d2(centres[c]);if(q<d){d=q;best=c;}}
    sizes[best]++;sse+=d;
  }
  return KResult(centres,sizes,sse);
}

List<Point2> parseCsv(String s) {
  final out=<Point2>[];
  final lines=s.split(RegExp(r'\r?\n'));
  for(var i=0;i<lines.length;i++){
    final line=lines[i].trim();
    if(line.isEmpty) continue;
    final cells=line.split(RegExp(r'[;,]'));
    if(cells.length<2) continue;
    final x=double.tryParse(cells[0].trim());
    final y=double.tryParse(cells[1].trim());
    if(x==null||y==null){if(i==0) continue; throw Exception('Erro na linha ${i+1}: esperadas coordenadas x,y.');}
    out.add(Point2(x,y));
  }
  if(out.length<3) throw Exception('O CSV deve conter pelo menos 3 pares x,y.');
  return out;
}

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});
  @override
  State<AgentPage> createState()=>_AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  int? ordinal;
  List<Point2> points=[];
  String? fileName;
  Proposal? own;
  final Map<int,Proposal> proposals={};
  Proposal? winner;
  NearbyService? nearby;
  StreamSubscription? peersSub, requestsSub, payloadSub;
  final Map<String,dynamic> peers={};
  bool network=false;
  String status='Escolha o ordinal do agente e importe o CSV.';

  @override
  void dispose(){
    peersSub?.cancel();requestsSub?.cancel();payloadSub?.cancel();
    nearby?.dispose();super.dispose();
  }

  void message(String s){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> importCsv() async {
    final f=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['csv','txt'],withData:true);
    if(f==null)return;
    try{
      final bytes=f.files.single.bytes;
      if(bytes==null)throw Exception('Não foi possível ler o ficheiro.');
      final p=parseCsv(utf8.decode(bytes,allowMalformed:true));
      setState(() {
        points = p;
        fileName = f.files.single.name;
        own = null;
        proposals.clear();
        winner = null;
        status = '${p.length} pontos importados.';
      });
    }catch(e){message(e.toString());}
  }
  void calculate(){
    if(ordinal==null){message('Escolha o ordinal do agente.');return;}
    if(points.length<3){message('Importe primeiro um CSV.');return;}
    try{
      final r=kmeans(points,DateTime.now().microsecondsSinceEpoch ^ (ordinal!*7919));
      final p=Proposal(ordinal!,r.centres,r.sizes,r.sse);
      setState(() {
        own = p;
        proposals[ordinal!] = p;
        winner = null;
        status = 'K-means concluído.';
      });
    }catch(e){message(e.toString());}
  }
  Future<void> startNetwork() async {
    if(ordinal==null){message('Escolha o ordinal primeiro.');return;}
    if(network)return;
    final n=NearbyService(localDisplayName:'SWARM-AGENT-$ordinal',localPeerId:'swarm-agent-$ordinal');
    nearby=n;
    peersSub=n.discoveredPeersStream.listen((list){
      for(final p in list){if(p.displayName.toString().startsWith('SWARM-AGENT-') && p.displayName!='SWARM-AGENT-$ordinal'){peers[p.id.toString()]=p;}}
      if(mounted)setState(() => status = 'Agentes encontrados: ${peers.length}.');
    });
    requestsSub=n.connectionRequestsStream.listen((r) async {
      try{await n.acceptConnection(r.peer.id);if(mounted)setState(() => status = 'Ligação aceite de ${r.peer.displayName}.');}catch(e){message('Erro de ligação: $e');}
    });
    payloadSub=n.payloadReceivedStream.listen((payload){
      if(payload.type!=PayloadType.bytes||payload.bytes==null)return;
      try{
        final j=jsonDecode(utf8.decode(payload.bytes!));
        if(j['type']=='proposal'){
          final p=Proposal.fromJson(Map<String,dynamic>.from(j));
          if(p.agent!=ordinal){setState(() {
              proposals[p.agent] = p;
              winner = null;
              status = 'Recebida proposta do agente ${p.agent}.';
            });}
        }
      }catch(e){message('Mensagem inválida: $e');}
    });
    try{
      await n.startAdvertising(options:AdvertisingOptions(serviceId:'swarm-agent',strategy:DiscoveryStrategy.hybrid,securityMode:SecurityMode.autoAccept));
      await n.startDiscovery(options:const DiscoveryOptions(serviceId:'swarm-agent',strategy:DiscoveryStrategy.hybrid));
      setState(() {
        network = true;
        status = 'A anunciar e a procurar os outros agentes.';
      });
    }catch(e){message('Falha ao iniciar comunicação: $e');}
  }
  Future<void> connect(dynamic p) async {
    try{await nearby!.requestConnection(p);setState(() => status = 'Pedido enviado a ${p.displayName}.');}
    catch(e){message('Falha na ligação: $e');}
  }
  Future<void> sendProposal() async {
    if(own==null){message('Execute primeiro o K-means.');return;}
    if(nearby==null){message('Inicie a comunicação.');return;}
    try{
      await nearby!.sendBytesToAll(Uint8List.fromList(utf8.encode(jsonEncode(own!.toJson()))));
      setState(() => status = 'Proposta enviada aos agentes ligados.');
    }catch(e){message('Não foi possível enviar: $e');}
  }
  void choose() {
    if (ordinal == null) {
      message('Escolha o ordinal deste agente.');
      return;
    }
    if (proposals.length != 3) {
      message('São necessárias 3 propostas. Recebidas: ${proposals.length}/3.');
      return;
    }
    final selected = collectiveChoice();
    if (selected == null) return;
    setState(() {
      winner = selected;
      status = 'Solução selecionada: proposta do agente ${selected.agent}, por menor SSE.';
    });
  }

  // A ordenação polar considera a origem (0,0) do sistema de coordenadas do CSV.
  // Primeiro raio crescente; em caso de igualdade, ângulo crescente em [0, 2π).
  List<Point2> ordered(Proposal p) {
    final c = [...p.centres];
    double radius(Point2 q) => sqrt(q.x * q.x + q.y * q.y);
    double angle(Point2 q) {
      final a = atan2(q.y, q.x);
      return a < 0 ? a + 2 * pi : a;
    }
    c.sort((a, b) {
      final dr = radius(a) - radius(b);
      if (dr.abs() > 1e-9) return dr < 0 ? -1 : 1;
      return angle(a).compareTo(angle(b));
    });
    return c;
  }

  Proposal? collectiveChoice() {
    if (proposals.length != 3) return null;
    final all = proposals.values.toList()
      ..sort((a, b) {
        final sseCompare = a.sse.compareTo(b.sse);
        if (sseCompare != 0) return sseCompare;
        return a.agent.compareTo(b.agent);
      });
    return all.first;
  }

  Widget sectionCard(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 21),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget metric(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );

  Widget proposalCard(Proposal p, Proposal? selected) {
    final isSelected = selected?.agent == p.agent;
    return Card(
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Proposta do agente ${p.agent}',
              style: const TextStyle(fontWeight: FontWeight.bold))),
            if (isSelected) const Chip(label: Text('Selecionada')),
          ]),
          metric('SSE', p.sse.toStringAsFixed(5)),
          metric('Pessoas por cluster', p.sizes.join(' / ')),
          metric('Variância das dimensões', p.variance.toStringAsFixed(5)),
          const Divider(),
          ...p.centres.asMap().entries.map((e) => Text(
            'Centroide ${e.key+1}: (${e.value.x.toStringAsFixed(4)}, ${e.value.y.toStringAsFixed(4)})',
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final choice = winner;
    final orderedCentres = choice == null ? <Point2>[] : ordered(choice);
    final assigned = (ordinal != null && orderedCentres.length == 3)
        ? orderedCentres[ordinal! - 1] : null;
    final sortedProposals = proposals.values.toList()
      ..sort((a,b)=>a.agent.compareTo(b.agent));

    return Scaffold(
      appBar: AppBar(
        title: const Text('SWARM — Agente móvel'),
        actions: [
          IconButton(
            tooltip: 'Reiniciar ensaio',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() {
              own = null;
              proposals.clear();
              winner = null;
              status = 'Ensaio reiniciado. Importe novamente os dados.';
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          sectionCard('1. Identificação do agente', Icons.smartphone, [
            const Text('O utilizador escolhe o ordinal deste telemóvel.'),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Agente 1')),
                ButtonSegment(value: 2, label: Text('Agente 2')),
                ButtonSegment(value: 3, label: Text('Agente 3')),
              ],
              selected: ordinal == null ? <int>{} : <int>{ordinal!},
              emptySelectionAllowed: true,
              onSelectionChanged: (selection) => setState(() {
                ordinal = selection.isEmpty ? null : selection.first;
                own = null;
                proposals.clear();
                  winner = null;
                status = ordinal == null
                    ? 'Selecione um ordinal.'
                    : 'Este telemóvel é o Agente $ordinal.';
              }),
            ),
            if (ordinal != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Agente ativo: $ordinal',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ]),

          sectionCard('2. Dados de entrada', Icons.upload_file, [
            FilledButton.icon(
              onPressed: importCsv,
              icon: const Icon(Icons.folder_open),
              label: const Text('Escolher ficheiro CSV'),
            ),
            const SizedBox(height: 8),
            Text(fileName ?? 'Nenhum ficheiro selecionado'),
            metric('Localizações carregadas', '${points.length}'),
            const Text('Formato: x,y — uma pessoa por linha. Cabeçalho opcional. Use ponto decimal.'),
          ]),

          sectionCard('3. Cálculo do agente', Icons.hub, [
            const Text('O agente executa K-means localmente com K=3 e inicialização aleatória.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: calculate,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Executar K-means'),
            ),
            if (own != null) ...[
              const Divider(),
              metric('SSE calculado pelo agente', own!.sse.toStringAsFixed(5)),
              metric('Dimensão dos clusters', own!.sizes.join(' / ')),
              ...own!.centres.asMap().entries.map((e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${e.key+1}')),
                title: Text('Centroide ${e.key+1}'),
                subtitle: Text('x = ${e.value.x.toStringAsFixed(5)}; y = ${e.value.y.toStringAsFixed(5)}'),
              )),
            ],
          ]),

          sectionCard('4. Comunicação entre agentes', Icons.bluetooth, [
            const Text('Inicie a descoberta em cada telemóvel. Depois, estabeleça ligação aos outros dois agentes.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: startNetwork,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(network ? 'Descoberta iniciada' : 'Procurar outros agentes'),
            ),
            metric('Agentes detetados', '${peers.length}'),
            ...peers.values.map((peer) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(peer.displayName.toString()),
              trailing: FilledButton.tonal(
                onPressed: () => connect(peer),
                child: const Text('Estabelecer ligação'),
              ),
            )),
            const Divider(),
            FilledButton.icon(
              onPressed: sendProposal,
              icon: const Icon(Icons.send),
              label: const Text('Enviar centroides e SSE'),
            ),
            metric('Propostas recebidas', '${proposals.length} / 3'),
            if (proposals.length < 3)
              const Text('A decisão coletiva ficará disponível quando as três propostas estiverem recebidas.'),
          ]),

          sectionCard('5. Comparação das três soluções', Icons.compare_arrows, [
            if (sortedProposals.isEmpty)
              const Text('Ainda não existem propostas. Execute o K-means e troque os resultados.'),
            ...sortedProposals.map((p) => proposalCard(p, choice)),
            if (proposals.length == 3) ...[
              const Divider(),
              const Text('Regra: vence a proposta com o menor SSE. Em caso de igualdade, vence a proposta do agente com menor ordinal.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: choose,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Selecionar proposta com menor SSE'),
              ),
            ],
          ]),

          sectionCard('6. Decisão determinística dos agentes', Icons.groups, [
            if (choice == null)
              const Text('Aguardam-se as três propostas para identificar a solução com menor SSE.'),
            if (choice != null) ...[
              const Text('Não há votação. Cada agente aplica a mesma regra às mesmas três propostas; por isso, todos obtêm a mesma solução vencedora.'),
              const SizedBox(height: 8),
              ...[1,2,3].map((agentId) => ListTile(
                leading: CircleAvatar(child: Text('$agentId')),
                title: Text('Agente $agentId'),
                subtitle: Text('Seleciona a proposta do agente ${choice.agent} (menor SSE)'),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
              )),
              const Divider(),
              metric('Proposta selecionada', 'Agente ${choice.agent}'),
              metric('SSE vencedor', choice.sse.toStringAsFixed(5)),
            ],
          ]),

          sectionCard('7. Centroide atribuído a este telemóvel', Icons.my_location, [
            if (assigned == null)
              const Text('O centroide será apresentado depois de receber as três propostas e selecionar a de menor SSE.'),
            if (assigned != null) ...[
              Text('Agente $ordinal recebe o centroide de ordinal $ordinal, após ordenar os três centroides por x crescente (e y crescente em caso de empate).'),
              const SizedBox(height: 10),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text('CENTROIDE $ordinal',
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    Text('(${assigned.x.toStringAsFixed(5)}, ${assigned.y.toStringAsFixed(5)})',
                      style: Theme.of(context).textTheme.headlineSmall),
                  ]),
                ),
              ),
              const Text('Ordenação completa dos centroides vencedores:'),
              ...orderedCentres.asMap().entries.map((e) => ListTile(
                dense: true,
                leading: CircleAvatar(child: Text('${e.key+1}')),
                title: Text('(${e.value.x.toStringAsFixed(4)}, ${e.value.y.toStringAsFixed(4)})'),
                subtitle: Text('Atribuído ao Agente ${e.key+1}'),
                trailing: ordinal == e.key+1 ? const Icon(Icons.person_pin_circle) : null,
              )),
            ],
          ]),

          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 10),
                Expanded(child: Text('Estado: $status')),
              ]),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'Nota: os três telemóveis devem carregar exatamente o mesmo CSV. Cada agente calcula uma proposta independente. A decisão só é válida quando todos receberam as três propostas.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
