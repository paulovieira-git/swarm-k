# SWARM Mobile Agent — Flutter

Protótipo de aplicação para três telemóveis/agentes.

## Funcionalidades
- O utilizador escolhe o ordinal do agente (1, 2 ou 3).
- Importa um CSV de coordenadas x,y.
- Executa K-means independente com K=3.
- Apresenta os três centroides, SSE e número de pontos em cada cluster.
- Descobre e liga aos outros agentes através do pacote `nearby` (transporte híbrido Wi-Fi/LAN e BLE).
- Envia e recebe propostas com centroides e SSE.
- Apresenta as três propostas e seleciona deterministicamente a que tem menor SSE. Em empate exato, menor ordinal do agente proponente.
- Ordena os três centroides vencedores por raio polar crescente e, se os raios forem iguais, por ângulo polar crescente.
- O agente i recebe o centroide de posição i.
- Não há votação nem envio de votos entre agentes: todos aplicam a mesma regra às mesmas três propostas.

## Instalação
1. Instalar Flutter SDK e Android Studio/Xcode.
2. Criar estrutura nativa: `flutter create --platforms=android,ios swarm_mobile_agent`
3. Substituir `pubspec.yaml` e `lib/main.dart` pelos ficheiros deste pacote.
4. Executar `flutter pub get` e `flutter run`.

## CSV
Cabeçalho opcional; primeiras duas colunas x e y. Exemplo:
```csv
x,y
1.2,3.4
2.1,4.0
```
Usar ponto como separador decimal.

## Configuração de permissões
Consultar a documentação atual do pacote `nearby` para as permissões Android e as chaves de privacidade iOS correspondentes à versão instalada. O pacote utiliza descoberta/ligação peer-to-peer híbrida, que pode usar Wi-Fi/LAN ou BLE conforme a plataforma e as condições.

## Protocolo de ensaio
1. Instalar a app em três telemóveis físicos.
2. Escolher ordinais 1, 2 e 3.
3. Importar o mesmo CSV nos três.
4. Executar K-means nos três.
5. Iniciar descoberta e estabelecer ligações entre os agentes.
6. Enviar as três propostas.
7. Depois de cada app receber as três propostas, calcular a seleção local. Não há votação: todos aplicam a mesma regra.

## Regra de seleção e atribuição
- Seleção da proposta: menor SSE; em empate exato, menor ordinal do agente que gerou a proposta.
- Ordenação dos centroides da proposta vencedora: raio polar crescente relativamente à origem (0,0); em igualdade de raio, ângulo crescente em [0, 2π).
- Atribuição: agente 1 recebe centroide 1, agente 2 recebe centroide 2 e agente 3 recebe centroide 3.

## Limitações
- É código-fonte, não APK/IPA compilado.
- Testar em três dispositivos físicos.
- O CSV não é distribuído automaticamente: cada agente importa o mesmo ficheiro.
- A decisão é calculada localmente após receção das três propostas.
- A origem (0,0) é assumida como referência do sistema de coordenadas do CSV. Se o retângulo usar outra origem, a transformação para coordenadas polares deve ser ajustada.
