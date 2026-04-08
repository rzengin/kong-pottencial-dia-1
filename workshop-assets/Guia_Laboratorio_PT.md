# Guia do Laboratório: Kong Konnect

Este laboratório tem como objetivo demonstrar as capacidades de controle, segurança, transformação e observabilidade usando o Kong Konnect como Control Plane e um Data Plane local, administrado de forma completamente declarativa através do `deck`.

---

## 1. Preparação do Ambiente (Local e Konnect)

### A. Requisitos Básicos
1. Ter uma conta ativa no **Kong Konnect**.
2. Ter instalado no seu computador a CLI do **decK** (versão v1.40+), a ferramenta **curl**, e o aplicativo de desktop **Insomnia** (versão gratuita).
3. O Data Plane local do Kong já se encontra levantado de forma permanente para este laboratório.

### B. Identificação e Obtenção de Credenciais
Dado que o seu Data Plane já se encontra pré-configurado e operacional, você só precisa obter e configurar suas credenciais de acesso ao Konnect para gerenciar as políticas remotamente:
1. Identifique o seu **Control Plane** atribuído no Kong Konnect (terá o formato `cp-local-seu.nome`).
2. Acesse as preferências do seu perfil no Kong Konnect e gere um **Personal Access Token (PAT)** para usar com o `decK`.

### C. Verificação do Ambiente
Antes de iniciar o laboratório, valide se tudo funciona corretamente e se você tem conectividade plena:
1. **Sincronização Konnect:** Acesse a interface do seu Control Plane no Kong Konnect (seção *Data Plane Nodes*) e verifique se o seu nó (Data Plane) aparece conectado no estado **"In Sync"**.
2. **Conectividade CLI decK:** Configure as variáveis no seu terminal e execute um comando `ping` para validar se o `decK` se conecta com sucesso:
   ```bash
   export KONNECT_TOKEN="<seu-token-pat>"
   export CONTROL_PLANE_NAME="cp-local-seu.nome" # Substitua pelo seu nome exato
   deck gateway ping --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
   ```
   *O comando deve ser concluído com sucesso, o que confirma que as credenciais são válidas e você tem conexão com o Konnect.*

Se o Data Plane estiver em Sync e o comando inicial responder corretamente, você está pronto para começar!

---

## Fase 0: Design, Testes e Mocking de API (Insomnia)

Antes de expor a API através do Gateway, é fundamental construí-la e simular seu comportamento. Nesta atividade, a equipe de QA é protagonista.
1. **Importar a Coleção:** Clique em **Import** e importe a coleção `workshop-assets/insomnia/Insomnia_Workspace.json`. Isso carregará as requisições de teste na seção "Collections" da barra lateral.
2. **Importar o Design OpenAPI:** Clique novamente em **Import** na página inicial, e agora importe o arquivo `workshop-assets/insomnia/flights-api.yaml`. Isso aparecerá como um novo arquivo sob a seção **"Documents"**. Abra-o. Você vai notar que a aba inferior "Ruleset" marca **1 Erro** em vermelho (porque na rota `/customers` falta a propriedade obrigatória `description` dentro da resposta `200`).
   * **Exercício de QA:** Para solucionar este erro estrutural, vá até o bloco de código YAML de `/customers`, logo abaixo da linha que diz `'200':`. Insira uma nova linha respeitando a indentação, e digite `description: "Lista de clientes"`. O erro desaparecerá instantaneamente validando a sua especificação em 100%.
3. **Levantar o Simulador (Mock Server):** Como você está em um "Local Vault", o Insomnia exige um "Self Hosted Mock". Isso significa que usaremos nosso confiável servidor Mock para responder às requisições automáticas. No seu terminal, na raiz do projeto, execute este comando para levantar o Prism na porta `8080`:
```bash
docker rm -f prism_mock || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 -v $(pwd)/workshop-assets/insomnia/flights-api.yaml:/tmp/flights-api.yaml stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false
```
* **Teste o Mock:** Verifique se o servidor está respondendo corretamente executando `curl http://localhost:8080/flights` no seu terminal. Você deve ver um JSON com dados de voos imediatamente!
*(Opcionalmente, na seção Mock do Insomnia, você pode configurar o "Self Hosted URL" apontando para esta mesma `http://localhost:8080` para tê-lo documentado)*.
4. **Baterias de Testes:** Tanto nos pre-scripts das requisições quanto na aba "Runner", configuramos validações de ciclo de vida. Nós as usaremos no final do laboratório!

---

## 2. Execução do Laboratório com `deck`

A seguir gerenciaremos as políticas aplicando os arquivos `kong.yaml` localizados dentro de cada pasta de cenário.

*Nota: Certifique-se de manter ativas na sua sessão de terminal as variáveis exportadas `KONNECT_TOKEN` e `CONTROL_PLANE_NAME` definidas na etapa de validação.*

### Exercício 0: Preparação e Limpeza do ambiente
**O que queremos alcançar:** Garantir que o Control Plane esteja em um estado completamente em branco, removendo qualquer configuração prévia, e iniciar a infraestrutura de observabilidade necessária para o laboratório.

**Como se faz:**
Primeiro, levantamos os contêineres do stack LGTM (Grafana, Jaeger, Prometheus, Loki) e o servidor mock de backend (Prism):
```bash
# Stack de observabilidade
cd workshop-assets/observabilidad && docker compose up -d && cd ..

# Backend mock (Prism) na porta 8080
docker rm -f prism_mock 2>/dev/null || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 \
  -v $(pwd)/insomnia/flights-api.yaml:/tmp/flights-api.yaml \
  stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false
```

Em seguida, limpamos o ambiente do Konnect e estabelecemos a base de observabilidade (cenário 0):
```bash
deck gateway reset --force --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
deck gateway apply 00-setup/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validação):**
Faça uma chamada a qualquer rota na porta 8000:
```bash
curl -i http://localhost:8000/
# Você deve ver: 404 Not Found ({"message":"no Route matched with those values"})
```

### Exercício 1: Base de Roteamento e Observabilidade (01-base.yaml)
**O que queremos mostrar:** A criação de rotas diretas para o backend mock (Prism), encapsulando a rede local e expondo-a de forma segura, enquanto os plugins globais de observabilidade registram silenciosamente toda a atividade.

**Como se faz:**
```bash
deck gateway ping --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
deck gateway apply 01-base/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validação e Geração de Tráfego):**
Faça uma chamada à rota exposta na porta 8000 gerando tráfego de forma contínua para coletar telemetria inicial:
```bash
echo "Gerando tráfego inicial..."
for i in {1..20}; do curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/flights; sleep 0.2; done
```
*Este comando injetará múltiplas requisições. Nos próximos exercícios, as requisições gerarão rejeições (401, 403, 429) que também enriquecerão nossos dashboards.*

### Exercício 2: Controle de exposição por método (02-metodos.yaml)
**O que queremos mostrar:** Reduzir a superfície de ataque aceitando apenas solicitações do tipo GET em uma rota.

**Como se faz:**
```bash
deck gateway apply 02-metodos/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validação):**
```bash
curl -i http://localhost:8000/flights
# Retorna 200 OK

curl -i -X POST http://localhost:8000/flights
# Retorna 404 No Route Matched
```

### Exercício 3: Autenticação com Key Auth e Consumers (03-seguridad-auth.yaml)
**O que queremos mostrar:** Centralizar a autenticação no nível do gateway sem modificar o código do backend, identificando diferentes "Consumidores".

**Como se faz:**
```bash
deck gateway apply 03-seguridad-auth/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validação):**
```bash
# Sem chave rejeita a requisição:
curl -i http://localhost:8000/flights
# Retorna 401 Unauthorized

# Com a chave externa, permite a passagem:
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
# Retorna 200 OK
```

### Exercício 4: Autorização com ACL (04-seguridad-acl.yaml)
**O que queremos mostrar:** Além de saber quem você é (autenticação), o gateway valida se você tem permissão (grupo ACL `external` ou `internal`) para acessar um recurso específico.

**Como se faz:**
```bash
deck gateway apply 04-seguridad-acl/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validação):**
```bash
# O usuário externo tem acesso a /flights
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
# Retorna 200 OK

# O usuário interno é rejeitado
curl -i http://localhost:8000/flights -H "apikey: my-internal-key"
# Retorna 403 Forbidden
```

### Exercício 5: Rate Limiting diferenciado (05-rate-limiting.yaml)
**O que queremos mostrar:** Proteger o backend de abuso com cotas diferenciadas por consumidor: o usuário externo tem um limite de 5 requisições/minuto (demonstrável), o interno tem 3 (mas além disso é bloqueado pelo ACL ao tentar acessar `/flights`).

**Como se faz:**
```bash
deck gateway apply 05-rate-limiting/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validação):**
Execute o seguinte ciclo para o consumidor **externo** (limite de 5 requisições/minuto):
```bash
for i in {1..7}; do curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/flights -H "apikey: my-external-key"; done
```
*Você observará que as primeiras 5 requisições retornam `200 OK` e a partir da 6ª mudam para `429 Too Many Requests`.*

### Exercício 6: Transformações e Observabilidade (06-transformaciones.yaml)
**O que queremos mostrar:** Enriquecer as requisições para o backend e as respostas ao cliente alterando cabeçalhos dinamicamente, e injetar um ID de Correlação para facilitar o troubleshooting moderno.

**Como se faz:**
```bash
deck gateway apply 06-transformaciones/kong.yaml --konnect-token $KONNECT_TOKEN --konnect-control-plane-name "$CONTROL_PLANE_NAME"
```

**Impacto (Validação):**
Teste a rota de flights, observando os cabeçalhos de resposta (Response Transformers):
```bash
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
```
*Você deverá observar um novo cabeçalho `x-perceptiva: true` e o surgimento de `X-Kong-Request-Id` ou `x-correlation-id` gerado pelo gateway.*

### Exercício 7: Exploração da Observabilidade Integral Remota
**O que queremos mostrar:** Visualizar como as configurações globais que injetamos silenciosamente no Exercício 0 (File Log, Prometheus, OpenTelemetry e Loki HTTP Log) capturaram a telemetria de todo o laboratório.

**Entendendo a captura passiva:**
1. **Logs em File System:** Usando a variável previamente definida, inspecione os logs diretamente no contêiner com:
   ```bash
   docker exec -it $KONNECT_DATA_PLANE_NAME tail -f /tmp/kong-access.log
   ```
   *(Pressione `Ctrl+C` para sair).*
2. **Traces e Logs Centralizados:** Os envios são automatizados pela rede para o stack LGTM.
3. **Métricas no Prometheus:** O Kong expõe o endpoint em `http://localhost:8100/metrics`.

**Como visualizar os resultados no Stack Externo (Grafana, Jaeger, Loki, Prometheus):**
Como já iniciamos o stack integrado no Exercício 0, você só precisa se certificar de ter gerado o tráfego de teste e então:
1. **Jaeger (Traces):** Acesse [http://localhost:16686](http://localhost:16686). No painel principal, em "Service", selecione `kong-api-gateway` e clique em "Find Traces". Você poderá ver o ciclo de vida completo de cada requisição de rede e os tempos de latência do upstream graças ao plugin OpenTelemetry.
2. **Grafana (Logs e Métricas):** Acesse [http://localhost:3000](http://localhost:3000) (Usuário/Senha: `admin` / `admin`).
    - Vá para a seção **Explore** (ícone de bússola no painel esquerdo).
    - Selecione o Data Source **Loki** no canto superior esquerdo.
    - No painel de consulta (aba **Builder**), em **Label filters**, selecione o label `job`, e em `Select value` escolha `kong-gateway`.
    - Faça clique no botão azul **Run query** no canto superior direito. Você verá uma lista com todos os logs JSON de suas requisições!
    - Mude o Data Source para **Prometheus** para grafar métricas em tempo real explorando métricas como `kong_http_status` ou `kong_latency_bucket`.

---

### Exercício 08: Execução Automática da Bateria de Testes no Insomnia
**O que queremos mostrar:** Executar os Unit Tests automáticos programados pela equipe de QA, validando empiricamente que o Gateway do Kong protege a infraestrutura em cada cenário exigido.

**Configurando os Testes (Exemplo de Script):**
Para que o Runner funcione e não diga *"No test was detected"*, você deve parametrizar *scripts de verificação*. Vá para qualquer uma de suas requisições, abra a aba **Scripts** -> **After Response** (ou "Tests") e insira código validativo. Por exemplo, para sua `GET Flights (No Auth)`:

```javascript
insomnia.test("O Gateway deve bloquear a requisição com sucesso", () => {
    insomnia.expect(insomnia.response.code).to.eql(401);
    const body = insomnia.response.json();
    insomnia.expect(body.message).to.eql("No API key found in request");
});
```

**Como rodar a Coleção completa:**
1. Na barra lateral esquerda, clique no nome da sua coleção/pasta (`Kong QA Workshop`) para abrir suas opções.
2. Selecione **Run**, o que abrirá a visualização **Collection Runner**.
3. Certifique-se de que o Ambiente selecionado no canto superior esquerdo ainda seja o `Base Environment`.
4. Clique no botão roxo **Run**.
5. Sucesso! Você verá como o Insomnia dispara as APIs automaticamente e verificará todas as asserções, colorindo o relatório de verde (Passed) ao confirmar que as regras do Gateway do Kong respondem exatamente como o script de QA espera.

**Alternativa CI/CD: Execução por terminal (inso CLI)**
Para demonstrar à equipe de Arquitetura ou DevOps como essas políticas do Kong se integram nativamente em pipelines automatizados (GitHub Actions, GitLab CI, etc.), você pode rodar a mesma suíte sem precisar da interface gráfica usando a CLI oficial:

```bash
inso run test "Bateria Pruebas Escenario 08" \
  -e "Base Environment" \
  -w insomnia/Insomnia_Workspace.json
```
Você visualizará um belo relatório no terminal onde os três testes validam o fluxo na cor verde em apenas alguns milissegundos.

---

### Exercício 09: APIOps (O ciclo de vida da API Automatizado)
**O que queremos mostrar:** Demonstrar como as equipes de Platform Engineering e DevOps podem automatizar o ciclo de vida completo de uma API usando design *Contract-First* e testes CI/CD através do ecossistema Kong (`inso` + `decK`).

**Como fazer:**
1. No seu terminal (Mac/Linux), abra a pasta deste repositório.
2. Execute o emulador de Integração Contínua que preparamos para o workshop:
   ```bash
   ./09-apiops/emulador-ci.sh
   ```
3. Observe a saída no console. O pipeline executa de forma totalmente autônoma as **7 fases** do ciclo DevOps de APIs:

   | Fase | Ferramenta | Propósito |
   |------|------------|-----------|
   | FASE 1 | `inso lint spec` | Design-First QA — valida o contrato OpenAPI antes de tocar a infraestrutura |
   | FASE 2 | `deck file openapi2kong` | Specs-to-Kong — compila o design em configuração declarativa |
   | FASE 3 | `deck file validate` | Valida o YAML de infraestrutura gerado |
   | FASE 4 | `deck gateway diff` | Drift Detection — o que mudaria em produção |
   | FASE 5 | `inso run test` | Testes de comportamento sobre o gateway ativo |
   | FASE 6 ★ | Konnect API Catalog | Publica a spec OpenAPI no catálogo interno da organização |
   | FASE 7 ★ | Konnect Dev Portal | Publica a API para consumidores externos com auto-registro |

   > ★ As fases 6 e 7 requerem `KONNECT_TOKEN` e um Dev Portal ativo em `cloud.konghq.com/portals`.

4. Mostre à audiência o arquivo `workshop-assets/09-apiops/github-actions-demo.yml` para evidenciar como este script emulador se traduz exatamente em componentes reais do Github Actions prontos para uso.

---

### Exercício 10: Clustering, Escalabilidade e Autodescoberta
**O que queremos mostrar:** Demonstrar a robustez e imutabilidade da Infraestrutura do Kong. Vamos lançar um novo Data Plane (nó) simulando um evento de "Auto-Scaling" (escalonamento por alto tráfego) e provaremos que ele obtém sua configuração automaticamente e herda toda a observabilidade do Control Plane sem intervenção manual.

**Como fazer:**
1. Abra um terminal e lance o **segundo Data Plane** (que se conectará ao mesmo cluster na nuvem, mas em uma porta de destino diferente `8010` para não conflitar com o nó local original):
   ```bash
   ./10-clustering/dp2.sh
   ```
   *(Este comando usará os mesmos certificados mTLS, mas criará um contêiner chamado `kong_local_dp2`).*
2. **Teste a Replicação Base:** Envie uma solicitação testando a nova porta `8010`:
   ```bash
   curl -i http://localhost:8010/flights
   ```
   Você receberá um erro `401 Unauthorized`. Ele herdou imediatamente as regras de segurança sem que você tocasse em um único arquivo de configuração!
3. **Teste de Observabilidade:** 
   - Acesse o **Jaeger** (http://localhost:16686). Busque por traces recentes. Você verá que as requisições para a porta `8010` já enviaram seus traces OpenTelemetry.
   - Acesse o **Grafana** -> **Explore** -> **Loki** (http://localhost:3000). Busque por `{job="kong-gateway"}` e você verá novos logs JSON emitidos pelo seu novo nó secundário.

---

## 3. Encerramento e Revisão no Konnect Analytics
Acesse **Kong Konnect -> Analytics -> Explorer**. 
Filtre pelos últimos 15 ou 30 minutos e você poderá observar todo o tráfego gerado de maneira agregada:
- Quantidade de requisições.
- Desmembramento de erros (401, 403, 404, 429).
- Métricas de latência do Kong vs Latência do backend, evidenciando o impacto mínimo do Gateway e a visibilidade universal obtida sem tocar em uma linha de código do backend.

---

## Anexo: Anatomia da Observabilidade no Kong

Abaixo, analisaremos os dados brutos que o Kong gera para entender a riqueza de contexto que ele fornece para a observabilidade.

### 1. Exemplo de um Log de Acesso (JSON)
Este é o registro bruto que o Kong grava usando o plugin `file-log` (e que o Promtail envia para o Loki). Ele é formatado em JSON estruturado, o que o torna perfeito para ser indexado e consultado no Grafana:

```json
{
  "request": {
    "method": "GET",
    "uri": "/flights",
    "url": "http://localhost:8000/flights",
    "headers": {
      "user-agent": "curl/8.7.1",
      "x-consumer-username": "App-External",
      "x-correlation-id": "76dd9197-afbc-489f-a75c-ca02ac99b027",
      "traceparent": "00-3a226e00876e9040af48d73dcb05105a-15e8880040e4b6fc-00"
    }
  },
  "response": {
    "status": 200,
    "size": 814,
    "headers": {
      "x-kong-upstream-latency": "4",
      "x-kong-proxy-latency": "1"
    }
  },
  "latencies": {
    "proxy": 4,
    "kong": 1,
    "request": 5
  },
  "consumer": {
    "username": "App-External"
  },
  "trace_id": {
    "w3c": "3a226e00876e9040af48d73dcb05105a"
  }
}
```

**Explicação de suas partes:**
- **`request` & `response`**: Contêm toda a informação L7 (HTTP) interceptada. Destacam-se o `x-consumer-username` (identidade de quem faz a chamada após avaliar o API Key) e o `x-correlation-id` injetado por nosso plugin de transformação.
- **`latencies`**: Detalha matematicamente o tempo de vida da requisição. `kong` (1ms) é o tempo que o Kong processou plugins, `proxy` (4ms) é o tempo de espera até o backend. O total (`request`) foi de 5ms.
- **`trace_id`**: Contém o ID do padrão W3C (`3a226e0087...`), que o Kong envia idêntico para OTLP (Jaeger), garantindo que este log possa ser cruzado 1:1 com a traça de rede visual no painel.

### 2. Anatomia de uma Traça (OpenTelemetry)
Ao explorar no Jaeger assumindo o mesmo `trace_id` (`3a226e00876e9040af48d73dcb05105a`), você observará um grafo temporal (diagrama de Gantt) estruturado em "Spans" (Intervalos).

Por baixo dos panos, o que o Kong Gateway despachou para o coletor OTLP do Jaeger foi um bloco JSON idêntico a este, correlacionando-se visualmente com o log:

```json
{
  "traceID": "3a226e00876e9040af48d73dcb05105a",
  "spans": [
    {
      "spanID": "94429ad510ac4134",
      "operationName": "kong",
      "duration": 5000,
      "tags": [
        { "key": "http.status_code", "type": "int64", "value": 200 },
        { "key": "http.url", "type": "string", "value": "http://localhost/flights" },
        { "key": "span.kind", "type": "string", "value": "server" }
      ]
    },
    {
      "spanID": "7bb591986f4c57a0",
      "operationName": "kong.access.plugin.key-auth",
      "duration": 570,
      "tags": [ { "key": "span.kind", "type": "string", "value": "internal" } ]
    },
    {
      "spanID": "a1ca33afbccca6fc",
      "operationName": "kong.balancer",
      "duration": 4000,
      "tags": [
        { "key": "peer.service", "type": "string", "value": "flights" },
        { "key": "net.peer.name", "type": "string", "value": "host.docker.internal" }
      ]
    }
  ],
  "processes": {
    "p1": { "serviceName": "kong-api-gateway" }
  }
}
```

Cada traça do Kong divide-se tipicamente nestes componentes visuais na interface gráfica:
1. **Span Principal (Root):** Representa o ciclo completo desde que o cliente atingiu o Kong até o Kong devolver a resposta (`duration`: ~5ms).
2. **Span de Gateway (Processamento no Kong):** Um segmento que evidencia quanto tempo o Kong investiu executando plugins (`key-auth`, `correlation-id`, etc.) antes de retransmitir (ex: 1ms).
3. **Span de Upstream:** O segmento (`kong.balancer`) que mostra a conexão de rede e o processamento final no backend host (ex: 4ms). 

Graças a isso, se um serviço demorar 5 segundos para responder, a traça e o log mostrarão imediatamente se o gargalo provém de uma política complexa dentro do Gateway ou se é puramente lentidão do microsserviço final, eliminando disputas ("finger-pointing") entre equipes de desenvolvimento e arquitetura.
