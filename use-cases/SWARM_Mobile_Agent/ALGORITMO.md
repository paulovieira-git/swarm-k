# Algoritmo SWARM — seleção da solução e atribuição dos centroides

1. Os três agentes importam o mesmo CSV de coordenadas (x,y).
2. Cada agente executa K-means com K=3, usando inicialização independente.
3. Cada agente calcula e envia a sua proposta: três centroides e SSE (a aplicação também apresenta as dimensões dos clusters).
4. Cada aplicação reúne as três propostas e seleciona a que tem o menor SSE. Em caso de igualdade exata, usa-se o menor ordinal do agente proponente como desempate. Não existe votação nem troca de votos: a regra é determinística e igual para todos.
5. Na proposta vencedora, os três centroides são ordenados em coordenadas polares relativamente à origem (0,0) do CSV:
   - primeiro, raio crescente: r = sqrt(x²+y²);
   - em caso de igualdade de raio, ângulo crescente: θ = atan2(y,x), convertido para [0,2π).
6. O agente ordinal i recebe o centroide na posição i dessa ordenação.

Nota: esta versão usa o menor SSE como critério de escolha da proposta. A variância dos tamanhos dos clusters pode continuar a ser apresentada como métrica descritiva, mas não participa na seleção.
