# Azure Cosmos DB on a private network (Terraform)

Deploys an Azure Cosmos DB (NoSQL API) account reachable **only** through a
private endpoint inside a VNet.

## What gets created

| Resource | Purpose |
|---|---|
| Resource group | Holds everything |
| VNet `10.20.0.0/16` | Private network |
| `snet-app` `10.20.1.0/24` + NSG | Where your workloads run |
| `snet-private-endpoints` `10.20.2.0/24` + NSG | Hosts the Cosmos private endpoint; only `snet-app` may reach it on 443 |
| Cosmos DB account | `public_network_access_enabled = false`, TLS 1.2, Entra ID auth only (keys disabled), continuous backup, serverless by default |
| SQL database + containers | Configurable via `cosmos_database_name` / `cosmos_containers` |
| Private DNS zone `privatelink.documents.azure.com` | Linked to the VNet so `<account>.documents.azure.com` resolves to the private IP |
| Private endpoint (`Sql` subresource) | Private IP for Cosmos in the PE subnet |
| Cosmos SQL role assignments | Optional, for identities in `cosmos_data_contributor_principal_ids` |

## Usage

```bash
cd infra/azure-cosmos-private
cp terraform.tfvars.example terraform.tfvars   # set subscription_id etc.
az login
terraform init
terraform plan
terraform apply
```

## Connecting

- Run clients inside the VNet (VM, AKS, App Service / Functions with VNet
  integration into `snet-app`, or a peered VNet / VPN / ExpressRoute that uses
  the linked private DNS zone).
- Account keys are disabled; authenticate with a managed identity
  (`DefaultAzureCredential`) and add its object ID to
  `cosmos_data_contributor_principal_ids`.
- From outside the VNet the endpoint is unreachable by design. Running
  `terraform apply` itself only touches the control plane, so it works from
  anywhere.

## Notes

- Set `cosmos_serverless = false` for provisioned throughput (then add
  `throughput`/`autoscale_settings` to the database or containers).
- For peered/hub VNets, link the same private DNS zone to them as well.
