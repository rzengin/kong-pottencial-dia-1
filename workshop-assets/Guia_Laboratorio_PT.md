# Guia do Laboratório: Kong Konnect

Este laboratório tem como objetivo demonstrar as capacidades de controle, segurança, transformação e observabilidade usando o Kong Konnect como Control Plane e um Data Plane local, administrado de forma completamente declarativa através do `deck`.

---

## 1. Preparação do Ambiente (Local e Konnect)

### A. Requisitos Básicos
1. Ter uma conta ativa no **Kong Konnect**.
2. Ter instalado no seu computador a CLI do **decK** (versão v1.40+), a ferramenta **curl**, e o aplicativo de desktop **Insomnia** (versão gratuita).
3. O Data Plane local do Kong já se encontra levantado de forma permanente para este laboratório.

### B. Identificação e Configuração de Credenciais
Como o seu Data Plane já está pré-configurado e operacional, você só precisa obter e configurar suas credenciais de acesso ao Konnect:
1. Identifique o seu **Control Plane** atribuído no Kong Konnect (terá o formato `cp-local-seu.nome`).
2. Acesse as preferências do seu perfil no Kong Konnect e gere um **Personal Access Token (PAT)**.
3. Exporte suas credenciais no terminal. **Mantenha-as ativas durante todo o laboratório:**
   ```bash
   export KONNECT_TOKEN="<seu-token-pat>"
   export CONTROL_PLANE_NAME="cp-local-seu.nome"  # Substitua pelo seu nome exato
   ```
4. Gere o arquivo de configuração do `decK` (`.deck.yaml`) com essas credenciais:
   ```bash
   cd workshop-assets/
   bash 00-setup/generate-deck-config.sh
   ```
   > A partir deste ponto, todos os comandos `deck` leem o token e o Control Plane automaticamente a partir do `.deck.yaml`. Não é necessário passar parâmetros adicionais.

### C. Verificação do Ambiente
Antes de iniciar o laboratório, valide se tudo funciona corretamente:
1. **Sincronização Konnect:** Acesse a interface do seu Control Plane no Kong Konnect (seção *Data Plane Nodes*) e verifique se o seu nó aparece no estado **"In Sync"**.
2. **Conectividade CLI decK:**
   ```bash
   deck gateway ping
   ```
   *Deve responder corretamente, confirmando que as credenciais são válidas e você tem conexão com o Konnect.*

Se o Data Plane estiver em Sync e o ping responder corretamente, você está pronto para começar!

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

> 💡 **Nota sobre credenciais:** Todos os comandos `deck` deste laboratório lêem automaticamente o token e o Control Plane do arquivo `.deck.yaml` localizado em `workshop-assets/`. Não é necessário passar `--konnect-token` nem `--konnect-control-plane-name` em cada comando.

### Exercício 0: Preparação e Limpeza do ambiente
**O que queremos alcançar:** Garantir que o Control Plane esteja em um estado completamente em branco, removendo qualquer configuração prévia, e iniciar a infraestrutura de observabilidade necessária para o laboratório.

**Como se faz:**
Primeiro, levantamos os contêineres do stack LGTM (Grafana, Jaeger, Prometheus, Loki) e o servidor mock de backend (Prism):
```bash
# Stack de observabilidade (reinicio limpo)
cd workshop-assets/observabilidad
docker compose down
docker compose up -d
cd ..

# Backend mock (Prism) na porta 8080
docker rm -f prism_mock 2>/dev/null || true
docker run -d --platform linux/amd64 --name prism_mock -p 8080:4010 \
  -v $(pwd)/insomnia/flights-api.yaml:/tmp/flights-api.yaml \
  stoplight/prism:5 mock -h 0.0.0.0 /tmp/flights-api.yaml -m false
```

Em seguida, limpe o ambiente completo do Konnect e estabeleça o estado inicial:

**Limpeza completa (recomendada):**
```bash
source ~/.zshrc && bash cleanup.sh
```
> ⚠️ **Importante:** O `source ~/.zshrc` é necessário para que `KONNECT_TOKEN` esteja disponível na sessão antes de executar o script. Sem ele, o Terraform fica aguardando input interativo e o processo trava silenciosamente.

Este script apaga **tudo** criado durante o laboratório (4 etapas):
- 🗑️ **Catalog Services + Catalog APIs** → via REST API do Konnect
- 🗑️ **API Products + Dev Portal** → via Terraform
- 🗑️ **Gateway** → serviços, rotas, plugins, consumers (deck reset)
- 🗑️ **Docker** → Prism mock, stack LGTM, DP2

Uma vez limpo, estabeleça o estado inicial:
```bash
deck gateway sync 00-setup/kong.yaml
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
deck gateway ping
deck gateway sync 01-base/kong.yaml
```

**Impacto (Validação e Geração de Tráfego):**
Faça uma chamada à rota exposta na porta 8000 gerando tráfego de forma contínua para coletar telemetria inicial.
> 💡 Neste cenário ainda **não há autenticação**, portanto as requisições funcionam sem API key:
```bash
echo "Gerando tráfego inicial..."
for i in {1..20}; do curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/flights; sleep 0.2; done
```
*Este comando injetará múltiplas requisições (todas devem responder 200). Nos próximos exercícios, as requisições gerarão rejeições (401, 403, 429) que também enriquecerão nossos dashboards.*

### Exercício 2: Autenticação com Key Auth e Consumers (02-seguridad-auth.yaml)
**O que queremos mostrar:** Centralizar a autenticação no nível do gateway sem modificar o código do backend, identificando diferentes "Consumidores".

**Como se faz:**
```bash
deck gateway sync 02-seguridad-auth/kong.yaml
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

> 💡 **Nota sobre Laboratórios Opcionais:** Os exercícios de 3 a 6 são **modulares e independentes**. Como o laboratório de Autenticação (02) foi habilitado permanentemente, você pode avançar direto para o Exercício 7 a qualquer momento sem que nada quebre! Se pular os intermediários, a sua API funcionará perfeitamente e focará apenas no essencial.

### Exercício 3: **(Opcional)** Controle de exposição por método (03-metodos-opcional)
**O que queremos mostrar:** Reduzir a superfície de ataque aceitando apenas solicitações do tipo GET em uma rota.

**Como se faz:**
```bash
deck gateway sync 03-metodos-opcional/kong.yaml
```

**Impacto (Validação):**
```bash
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
# Retorna 200 OK

curl -i -X POST http://localhost:8000/flights -H "apikey: my-external-key"
# Retorna 404 No Route Matched
```

### Exercício 4: **(Opcional)** Autorização com ACL (04-seguridad-acl-opcional)
**O que queremos mostrar:** Além de saber quem você é (autenticação), o gateway valida se você tem permissão (grupo ACL `external` ou `internal`) para acessar um recurso específico.

**Como se faz:**
```bash
deck gateway sync 04-seguridad-acl-opcional/kong.yaml
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

### Exercício 5: **(Opcional)** Rate Limiting diferenciado (05-rate-limiting-opcional)
**O que queremos mostrar:** Proteger o backend de abuso com cotas diferenciadas por consumidor: o usuário externo tem um limite de 5 requisições/minuto (demonstrável), o interno tem 3 (mas além disso é bloqueado pelo ACL ao tentar acessar `/flights`).

**Como se faz:**
```bash
deck gateway sync 05-rate-limiting-opcional/kong.yaml
```

**Impacto (Validação):**
Execute o seguinte ciclo para o consumidor **externo** (limite de 5 requisições/minuto):
```bash
for i in {1..7}; do curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/flights -H "apikey: my-external-key"; done
```
*Você observará que as primeiras 5 requisições retornam `200 OK` e a partir da 6ª mudam para `429 Too Many Requests`.*

### Exercício 6: **(Opcional)** Transformações (06-transformaciones-opcional)
**O que queremos mostrar:** Enriquecer as requisições para o backend e as respostas ao cliente alterando cabeçalhos dinamicamente,.

**Como se faz:**
```bash
deck gateway sync 06-transformaciones-opcional/kong.yaml
```

**Impacto (Validação):**
Teste a rota de flights, observando os cabeçalhos de resposta (Response Transformers):
```bash
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
```
*Você deverá observar um novo cabeçalho `x-perceptiva: true`.*


### Exercício 7: Rastreabilidade com Correlation ID (07-correlation-id.yaml)
**O que queremos demonstrar:** Injetar um ID único (Correlation ID) em cada solicitação para facilitar o rastreamento e a rastreabilidade através de microsserviços.

**Como fazer:**
```bash
deck gateway sync 07-correlation-id/kong.yaml
```

**Impacto (Validação):**
Teste a API e verifique o surgimento do header injetado `x-correlation-id`.
```bash
curl -i http://localhost:8000/flights -H "apikey: my-external-key"
```
*Você observará o valor UUID retornado, o qual será chave para um troubleshooting rápido. Este mesmo ID viverá nos logs que revisaremos a seguir.*

### Exercício 8: Exploração da Observabilidade Integral Remota
**O que queremos mostrar:** Visualizar como as configurações globais (File Log, Prometheus e OpenTelemetry) capturaram a telemetria de todo o laboratório em tempo real.

**Passo 1 — Reiniciar o Stack e Aplicar a configuração de observabilidade completa:**
Para que o OpenTelemetry Collector assuma como intermediário (proxy de telemetria), reiniciaremos o stack do Docker e faremos o deploy da política na nuvem:

```bash
cd observabilidad/
docker compose down
docker compose up -d
cd ..
deck gateway sync 08-observabilidad/kong.yaml
```

**Passo 2 — Gerar tráfego misto para popular os dashboards:**
> 💡 A partir do E08, o serviço `/flights` mantém Key Auth. Use a API key em todos os requests bem-sucedidos:
> ⚠️ Se aparecer um `429` no final, é normal — o rate limit do App-External (20 req/min) pode estar acumulado de sessões anteriores. Aguarde 1 minuto e tente novamente.
```bash
# 15 requests bem-sucedidos (200) — margem segura abaixo do limite de 20/min
for i in {1..15}; do
  curl -s -o /dev/null -w "Code: %{http_code}\n" \
    -H "apikey: my-external-key" http://localhost:8000/flights
  sleep 0.2
done

# 10 requests sem key (401 — tráfego não autenticado)
for i in {1..10}; do
  curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/flights
  sleep 0.1
done

# 10 requests no endpoint de debug (sem auth)
for i in {1..10}; do
  curl -s -o /dev/null -w "Code: %{http_code}\n" http://localhost:8000/debug/headers
  sleep 0.1
done
```

**Passo 3 — Inspecionar logs no Data Plane local:**
```bash
# O contêiner do Data Plane se chama kong_local_dp neste laboratório.
# Se tiver dúvida, confirme com:
docker ps --format '{{.Names}}' | grep kong

# Ver logs de acesso em tempo real:
docker exec -it kong_local_dp tail -f /tmp/kong-access.log
```
*(Pressione `Ctrl+C` para sair.)*

**Passo 4 — Verificar métricas Prometheus pelo terminal:**
```bash
curl -s http://localhost:8100/metrics | grep kong_http_requests_total
```

**Passo 5 — Inspecionar intercepção pelo OpenTelemetry Collector:**
Neste cenário, o OTel Collector atua como roteador intermediário transparente. Ele intercepta as traças geradas pelo Kong antes que alcancem o Jaeger.
```bash
docker compose -f observabilidad/docker-compose.yaml logs otel-collector
```
*(Você verá no console a estrutura detalhada dos "Spans" interceptados em tempo real, como `kong.balancer` ou `kong.header_filter`).*

**Passo 5.1 — (Opcional) Demonstração Avançada: Filtrando Trazas no Collector**
Podemos demonstrar o poder de roteamento do Collector eliminando traças lixo (ex: pings de healthcheck ou debug) antes que alcancem o banco de dados do Jaeger, economizando custos.
1. Edite o arquivo `observabilidad/config/otel-collector.yaml`.
2. Observe que deixamos um bloco preparado `filter/exclude_debug` que ignora (`drop`) todas as traças onde o atributo `peer.service` é igual a `"debug-headers"`.
3. Para ativar, desça até o final do arquivo na seção `pipelines.traces.processors` e adicione o filtro à lista, deixando assim:
   `processors: [filter/exclude_debug, batch]`
4. Reinicie o Collector: `docker compose -f observabilidad/docker-compose.yaml restart otel-collector`
5. Gere requisições para `http://localhost:8000/debug/headers` e demonstre que **nenhuma** nova requisição desse serviço chega ao log do Collector, enquanto o serviço `/flights` continua passando normalmente!

**Passo 6 — Visualizar no Stack Externo (Grafana, Jaeger, Loki, Prometheus):**
1. **Jaeger (Traces):** Acesse [http://localhost:16686](http://localhost:16686). Em "Service", selecione `kong-api-gateway` → **Find Traces**. O Jaeger continuará exibindo o ciclo de vida completo da requisição, mas agora documentaremos que os dados foram roteados através do Collector.
2. **Grafana (Logs e Métricas):** Acesse [http://localhost:3000](http://localhost:3000) (Usuário/Senha: `admin` / `admin`).
    - Vá para **Explore** (ícone de bússola no painel esquerdo).
    - Selecione o Data Source **Loki**.
    - Em **Label filters**, selecione `job` = `kong-gateway` → **Run query**. Você verá todos os logs JSON estruturados.
    - Mude para o Data Source **Prometheus** e explore métricas como `kong_http_requests_total` ou `kong_latency_bucket`.

---

### Exercício 09: Execução Automática da Bateria de Testes no Insomnia
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

### Exercício 10: APIOps — Konnect Reference Platform Model

**O que queremos mostrar:** Implementar o ciclo de vida completo de APIs seguindo o modelo oficial do Kong: a **Konnect Reference Platform**. Este modelo define como as equipes de Platform Engineering e as equipes de API colaboram de forma declarativa usando `decK`, `Terraform` e `inso`, seguindo os mesmos 3 workflows que usa o projeto de referência **KongAirlines**.

> 📖 Referência oficial: https://developer.konghq.com/konnect-reference-platform/apiops/

---

#### Arquitetura Multi-Equipe (Modelo KongAirlines)

A Reference Platform divide responsabilidades entre **dois papéis**:

| Papel | Responsabilidade | Arquivos neste workshop |
|-------|-----------------|-------------------------|
| **Platform Team** | Plugins globais (observabilidade, segurança, tráfego), ruleset de conformance, gestão de plataforma (Terraform) | `platform-team/` |
| **API Teams** | OpenAPI Spec de sua API, plugins próprios (transformação, validação) | `flights-team/`, `bookings-team/`, etc. |

A estrutura de arquivos resultante em `10-apiops/`:

```
10-apiops/
│
├── platform-team/                    # Platform Team — plugins globais
│   ├── plugins-observabilidade.yaml   # prometheus + file-log + opentelemetry
│   └── linting-rules.yaml             # Ruleset de conformance (deck file lint)
│
├── flights-team/                     # API Team — Flights API
│   └── plugins-equipo.yaml            # correlation-id + response-transformer
│
├── bookings-team/   customers-team/   routes-team/
│   └── plugins-equipo.yaml            # correlation-id (próprio de cada equipe)
│
├── env/
│   └── local.env.yaml                 # Variáveis de ambiente (URLs de backend)
├── terraform/                         # Platform resources: Portal, Catalog, API Products
└── emulador-ci.sh                     # Orquestrador dos 3 workflows
```

---

#### Os 3 Workflows da Reference Platform

O pipeline executa **3 workflows em sequência**, com uma "aprovação" entre cada um (em GitHub Actions real: um Pull Request aprovado pelo Platform Team):

```
[Workflow 1] OpenAPI → decK
      ↓  (PR simulado — em CI real: revisão do Platform Team)
[Workflow 2] Stage decK Changes (diff)
      ↓  (PR simulado — em CI real: revisão de mudanças no Gateway)
[Workflow 3] decK Sync  ← único ponto de implantação no Gateway
      +
[Fase 4]    Terraform   ← API Products, Dev Portal, Service Catalog
```

---

#### Como executar

**Pré-requisitos:**
- Terraform instalado (`brew install terraform`)
- Variáveis exportadas: `KONNECT_TOKEN`, `CONTROL_PLANE_NAME`

Você tem duas opções para executar este cenário: usar o emulador de CI (script) ou executar os comandos passo a passo manualmente para entender o processo com profundidade.

##### Opção 1: Execução Automatizada (Emulador CI)
```bash
cd workshop-assets/
./10-apiops/emulador-ci.sh
```

##### Opção 2: Execução Manual Passo a Passo (The Hard Way)
Se você quer entender exatamente o que o pipeline faz por baixo dos panos, execute estes comandos um por um a partir do diretório `workshop-assets/`:

**WORKFLOW 1 — OpenAPI → decK**

```bash
# 1.1 OAS Conformance (Validação de design)
inso lint spec insomnia/flights-api.yaml

# 1.2 Compilar OpenAPI para decK e etiquetar por equipe
deck file openapi2kong -s insomnia/flights-api.yaml | deck file add-tags --selector='$..services[*]' flights-team -o 10-apiops/flights-base.yaml
deck file openapi2kong -s 10-apiops/specs/bookings-api.yaml | deck file add-tags --selector='$..services[*]' bookings-team -o 10-apiops/bookings-base.yaml
deck file openapi2kong -s 10-apiops/specs/customers-api.yaml | deck file add-tags --selector='$..services[*]' customers-team -o 10-apiops/customers-base.yaml
deck file openapi2kong -s 10-apiops/specs/routes-api.yaml | deck file add-tags --selector='$..services[*]' routes-team -o 10-apiops/routes-base.yaml

# 1.3 Injetar plugins próprios de cada equipe (Ex: correlation-id, transformações)
deck file add-plugins -s 10-apiops/flights-base.yaml 10-apiops/flights-team/plugins-equipo.yaml -o 10-apiops/flights-plugins.yaml
deck file add-plugins -s 10-apiops/bookings-base.yaml 10-apiops/bookings-team/plugins-equipo.yaml -o 10-apiops/bookings-plugins.yaml
deck file add-plugins -s 10-apiops/customers-base.yaml 10-apiops/customers-team/plugins-equipo.yaml -o 10-apiops/customers-plugins.yaml
deck file add-plugins -s 10-apiops/routes-base.yaml 10-apiops/routes-team/plugins-equipo.yaml -o 10-apiops/routes-plugins.yaml

# 1.4 Unificar configurações de todas as APIs
deck file render 10-apiops/flights-plugins.yaml 10-apiops/bookings-plugins.yaml 10-apiops/customers-plugins.yaml 10-apiops/routes-plugins.yaml -o 10-apiops/kong-from-oas.yaml

# 1.5 Platform Team injeta plugins globais (Ex: Prometheus, File Log)
deck file merge 10-apiops/kong-from-oas.yaml 10-apiops/platform-team/plugins-observabilidad.yaml -o 10-apiops/kong-merged.yaml

# 1.6 Validação offline da configuração resultante
deck file validate 10-apiops/kong-merged.yaml

# 1.7 Conformance do Platform Team (Validação de tags, nomes de rotas, etc.)
deck file lint -s 10-apiops/kong-merged.yaml --fail-severity warn 10-apiops/platform-team/linting-rules.yaml

# Guardar arquivo final que seria usado
cp 10-apiops/kong-merged.yaml kong-generated.yaml
```

**WORKFLOW 2 — Stage decK Changes**

```bash
# 2.1 Mostrar o que mudaria no Control Plane (Drift Detection)
deck gateway diff kong-generated.yaml
```

**WORKFLOW 3 — decK Sync**

```bash
# 3.1 Aplicar configurações no Control Plane (Único deploy no gateway)
deck gateway sync kong-generated.yaml
```

**FASE 4 — Recursos de Plataforma Konnect (Terraform)**

```bash
# Obter Control Plane ID
export CP_ID=$(curl -s -H "Authorization: Bearer $KONNECT_TOKEN" "https://${KONNECT_REGION:-us}.api.konghq.com/v2/control-planes?filter%5Bname%5D%5Beq%5D=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${CONTROL_PLANE_NAME:-Local Gateway}'))")" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')")

# Executar Terraform
cd 10-apiops/terraform
export TF_VAR_konnect_token=$KONNECT_TOKEN
export TF_VAR_konnect_server_url="https://${KONNECT_REGION:-us}.api.konghq.com"
export TF_VAR_control_plane_id=$CP_ID

terraform init
terraform plan
terraform apply -auto-approve
cd ../..
```

---

#### Detalhe de cada passo do pipeline

**WORKFLOW 1 — OpenAPI → decK** *(equivale a `konnect-spec-to-deck.yaml` do KongAirlines)*

| Passo | Comando | Quem faz? | Propósito |
|-------|---------|-----------|----------|
| 1.1 | `inso lint spec` | Platform Team | OAS conformance — valida o design antes de compilar |
| 1.2 | `deck file openapi2kong` + `add-tags` | Automático | Compila o OAS de cada equipe para config decK e etiqueta com o nome da equipe |
| 1.3 | `deck file add-plugins` | Cada API Team | Injeta plugins próprios da equipe (correlation-id, transformers) |
| 1.4 | `deck file render` | Automático | Unifica as configs de todas as equipes em `kong-from-oas.yaml` |
| 1.5 | `deck file merge` | Platform Team | Injeta plugins globais de observabilidade (prometheus, file-log, OTel) |
| 1.6 | `deck file validate` | Automático | Validação offline da config resultante |
| 1.7 | `deck file lint` | Platform Team | Conformance do Platform Team (tags, nomes de rotas, URLs) |
| 1.8 | `inso run test` | Automático | Bateria de testes de comportamento pré-implantação |

> **Resultado:** `kong-generated.yaml` — config unificada pronta para o próximo workflow.

**WORKFLOW 2 — Stage decK Changes** *(equivale a `konnect-stage-deck-change.yaml`)*

| Passo | Comando | Propósito |
|-------|---------|----------|
| 2.1 | `deck gateway diff` | Mostra exatamente o que mudaria no Control Plane. Em CI real, este diff é publicado como **comentário em um PR** para revisão do Platform Team antes de aprovar o deploy. |

**WORKFLOW 3 — decK Sync** *(equivale a `konnect-deck-sync.yaml`)*

| Passo | Comando | Propósito |
|-------|---------|----------|
| 3.1 | `deck gateway sync` | **Único ponto de implantação** no Gateway. Em CI real: dispara automaticamente ao mergear o PR do Workflow 2. |

**FASE 4 — Recursos de Plataforma Konnect (Terraform)**

Fora do escopo da Reference Platform decK, mas complementar: gerencia os recursos da plataforma Konnect de forma declarativa.

```bash
cd 10-apiops/terraform
export TF_VAR_konnect_token=$KONNECT_TOKEN
terraform init
terraform plan    # equivalente a "deck gateway diff" para a plataforma
terraform apply   # API Products + Portal + Catalog
terraform destroy # limpeza completa
```

| Recurso | Ferramenta |
|---------|------------|
| API Products (v2) + versões + specs + docs | Terraform |
| Dev Portal + publicações | Terraform |
| Service Catalog (`/v1/catalog-services`) | Terraform |
| Resource Mappings (`/v1/resource-mappings`) | `curl` (único residual — não suportado pelo provider ainda) |

---

#### O que você verá no console

O emulador mostra claramente a separação entre os 3 workflows:

```
╬══════════════════════════════════════════════════════════════════╪
║  WORKFLOW 1/3 │ OpenAPI → decK  (konnect-spec-to-deck)          ║
╚══════════════════════════════════════════════════════════════════╝
  [1.1] inso lint spec — OAS Conformance (ruleset do Platform Team)...
  ⚠️  A spec tem erros de design. Em CI real isso bloquearia o PR.
  [1.2] deck file openapi2kong — Compilando OAS → decK por equipe...
  ✅ flights-team: kong-from-oas gerado
  ✅ bookings-team, customers-team, routes-team: ok
  [1.3] deck file add-plugins — Injetando plugins de cada equipe...
  ✅ flights-team: correlation-id + response-transformer aplicados
  [1.4] deck file render — Unificando todas as APIs...
  ✅ Config unificada: kong-from-oas.yaml
  [1.5] deck file merge — Platform Team injeta plugins de observabilidade...
  ✅ Plugins de observabilidade do Platform Team fundidos
  ...
  🔀 PULL REQUEST SIMULADO → Workflow 1 concluído: pronto para Stage

╬══════════════════════════════════════════════════════════════════╪
║  WORKFLOW 2/3 │ Stage decK Changes  (konnect-stage-deck-change)  ║
╚══════════════════════════════════════════════════════════════════╝
  [2.1] deck gateway diff — Calculando mudanças vs. Control Plane...
  🔀 PULL REQUEST SIMULADO → diff revisado, aprovado para Sync

╬══════════════════════════════════════════════════════════════════╪
║  WORKFLOW 3/3 │ decK Sync  (konnect-deck-sync)                   ║
╚══════════════════════════════════════════════════════════════════╝
  [3.1] deck gateway sync — Aplicando ao Control Plane...
  ✅ Sync concluído
```

---

#### Separação de responsabilidades: quem faz o quê?

```
OpenAPI Spec (cada equipe escreve)
    │
    ▼
[flights-team/plugins-equipo.yaml]    Correlation ID, Response Transform
[bookings-team/plugins-equipo.yaml]   Correlation ID
        ↓ deck file add-plugins
        ↓ deck file render (une tudo)
        ↓
[platform-team/plugins-observabilidade.yaml]   Prometheus, file-log, OTel
        ↓ deck file merge
        ↓
[platform-team/linting-rules.yaml]    Governance: tags, nomes, URLs
        ↓ deck file lint
        ↓
     kong-generated.yaml  ─▶  deck gateway diff  ─▶  deck gateway sync
                                                              │
                                            Control Plane Konnect ✅
```

---

#### Conversa-chave com a audiência

> **"Por que não fazemos tudo com um único comando?"**
> A separação em 3 PRs com aprovação entre cada um é intencional: garante que nenhuma mudança no Gateway chegue a produção sem revisão humana. O Workflow 1 é responsabilidade da equipe de API, o Workflow 2 é revisão do Platform Team, e o Workflow 3 é o deploy automático apenas ao mergear. Isso implementa o **princípio dos 4 olhos** sobre a infraestrutura de APIs.

> **"O que acontece se alguém quebra a spec OpenAPI?"**
> O Passo 1.1 (`inso lint spec`) bloqueia o pipeline no ponto mais cedo possível — antes de gerar qualquer configuração de Gateway. O custo de detectar o erro é zero: nada foi consumido, nada foi implantado. Este é o valor central do modelo **Design-First / Contract-First**.

5. Mostre à audiência o arquivo `10-apiops/github-actions-declarativo.yml` para evidenciar como este pipeline se integra no GitHub Actions com os 3 workflows reais que usa o KongAirlines.

---

### Exercício 11: Clustering, Escalabilidade e Autodescoberta
**O que queremos mostrar:** Demonstrar a robustez e imutabilidade da Infraestrutura do Kong. Vamos lançar um novo Data Plane (nó) simulando um evento de "Auto-Scaling" (escalonamento por alto tráfego) e provaremos que ele obtém sua configuração automaticamente e herda toda a observabilidade do Control Plane sem intervenção manual.

**Como fazer:**
1. Abra um terminal e lance o **segundo Data Plane** (que se conectará ao mesmo cluster na nuvem, mas em uma porta de destino diferente `8010` para não conflitar com o nó local original):
   ```bash
   ./11-clustering/dp2.sh
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
