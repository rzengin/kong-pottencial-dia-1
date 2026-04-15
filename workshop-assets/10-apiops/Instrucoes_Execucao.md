# Guia de Execução: Cenário 10 - APIOps

Este documento contém as instruções detalhadas exclusivas para a execução do cenário **10-apiops**. Este laboratório simula o modelo oficial do Kong (Konnect Reference Platform), orquestrando o ciclo de vida completo onde múltiplas equipes (API Teams e Platform Team) interagem de forma independente e declarativa.

## Pré-requisitos
Antes de executar qualquer comando, certifique-se de que os seguintes pré-requisitos foram cumpridos:
- Terraform instalado (`brew install terraform`)
- Variáveis de ambiente configuradas no terminal: `KONNECT_TOKEN`, `CONTROL_PLANE_NAME`

Você pode optar por executar o cenário de forma automatizada ou manualmente passo a passo.

---

## Opção 1: Execução Automatizada (Emulador de CI)

Se você deseja demonstrar o pipeline completo rapidamente como se estivesse rodando no GitHub Actions ou GitLab CI, pode rodar o script que orquestra tudo.

A partir da raiz do projeto (`workshop-assets/`), execute:
```bash
cd workshop-assets/
./10-apiops/emulador-ci.sh
```

---

## Opção 2: Execução Manual Passo a Passo (The Hard Way)

Se o foco da demonstração for explicar tecnicamente às equipes de Arquitetura e DevOps o que ocorre nos bastidores de cada etapa do pipeline, execute estes comandos um a um a partir do diretório `workshop-assets/`:

### WORKFLOW 1 — OpenAPI → decK

A fase de design-first. Linta, compila, e unifica o trabalho de múltiplas equipes de produto e da equipe de plataforma.

```bash
# 1.1 OAS Conformance (Validação de design pela CLI)
inso lint spec insomnia/flights-api.yaml

# 1.2 Compilar OpenAPI para decK e etiquetar os recursos por equipe
deck file openapi2kong -s insomnia/flights-api.yaml | deck file add-tags --selector='$..services[*]' flights-team -o 10-apiops/flights-base.yaml
deck file openapi2kong -s 10-apiops/specs/bookings-api.yaml | deck file add-tags --selector='$..services[*]' bookings-team -o 10-apiops/bookings-base.yaml
deck file openapi2kong -s 10-apiops/specs/customers-api.yaml | deck file add-tags --selector='$..services[*]' customers-team -o 10-apiops/customers-base.yaml
deck file openapi2kong -s 10-apiops/specs/routes-api.yaml | deck file add-tags --selector='$..services[*]' routes-team -o 10-apiops/routes-base.yaml

# 1.3 Injetar plugins próprios das API Teams (Ex: correlation-id, transformator)
deck file add-plugins -s 10-apiops/flights-base.yaml 10-apiops/flights-team/plugins-equipo.yaml -o 10-apiops/flights-plugins.yaml
deck file add-plugins -s 10-apiops/bookings-base.yaml 10-apiops/bookings-team/plugins-equipo.yaml -o 10-apiops/bookings-plugins.yaml
deck file add-plugins -s 10-apiops/customers-base.yaml 10-apiops/customers-team/plugins-equipo.yaml -o 10-apiops/customers-plugins.yaml
deck file add-plugins -s 10-apiops/routes-base.yaml 10-apiops/routes-team/plugins-equipo.yaml -o 10-apiops/routes-plugins.yaml

# 1.4 Unificar e renderizar as configurações de todas as APIs
deck file render 10-apiops/flights-plugins.yaml 10-apiops/bookings-plugins.yaml 10-apiops/customers-plugins.yaml 10-apiops/routes-plugins.yaml -o 10-apiops/kong-from-oas.yaml

# 1.5 Platform Team injeta os plugins globais transversais (Ex: Prometheus, Logging)
deck file merge 10-apiops/kong-from-oas.yaml 10-apiops/platform-team/plugins-observabilidad.yaml -o 10-apiops/kong-merged.yaml

# 1.6 Validação offline da configuração macro resultante
deck file validate 10-apiops/kong-merged.yaml

# 1.7 Conformance do Platform Team (Validação de tags, URLs e naming conventions)
deck file lint -s 10-apiops/kong-merged.yaml --fail-severity warn 10-apiops/platform-team/linting-rules.yaml

# Salvar o artefato final limpo e pronto para os próximos passos
cp 10-apiops/kong-merged.yaml kong-generated.yaml
```

### WORKFLOW 2 — Stage decK Changes

O Drift Detection. Simula o momento em que a equipe verifica exatamente o impacto das mudanças no ambiente antes da aprovação final (Pull Request).

```bash
# 2.1 Mostrar o que mudaria no Control Plane (Drift)
deck gateway diff kong-generated.yaml
```

### WORKFLOW 3 — decK Sync

A Implantação. Este é o momento onde as políticas de gateway finalmente são enviadas ao Kong Konnect de maneira atômica e declarativa.

```bash
# 3.1 Aplicar configurações no Control Plane (Único deploy no gateway)
deck gateway sync kong-generated.yaml
```

### FASE 4 — Recursos de Plataforma Konnect (Terraform)

Após implantar as políticas ativas do proxy, gerenciamos via Terraform todos os atributos informativos da plataforma: Produtos de API, versões, documentos e Portal do Desenvolvedor.

```bash
# Obter ID do Control Plane ativo para o Terraform gerenciar o Service Catalog
export CP_ID=$(curl -s -H "Authorization: Bearer $KONNECT_TOKEN" "https://${KONNECT_REGION:-us}.api.konghq.com/v2/control-planes?filter%5Bname%5D%5Beq%5D=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${CONTROL_PLANE_NAME:-Local Gateway}'))")" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')")

# Transicionar para o ambiente de Terraform
cd 10-apiops/terraform
export TF_VAR_konnect_token=$KONNECT_TOKEN
export TF_VAR_konnect_server_url="https://${KONNECT_REGION:-us}.api.konghq.com"
export TF_VAR_control_plane_id=$CP_ID

# Rollout declarativo com Terraform
terraform init
terraform plan
terraform apply -auto-approve

# Retornar ao diretório base
cd ../..
```
