resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  name = "${var.prefix}-${random_string.suffix.result}"
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.app_subnet_prefix]
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_endpoint_subnet_prefix]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pe-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  # Only the app subnet may reach Cosmos DB over HTTPS.
  security_rule {
    name                       = "allow-app-to-cosmos"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.app_subnet_prefix
    source_port_range          = "*"
    destination_address_prefix = var.private_endpoint_subnet_prefix
    destination_port_range     = "443"
  }

  security_rule {
    name                       = "deny-vnet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# ---------------------------------------------------------------------------
# Cosmos DB (NoSQL API) - public network access disabled
# ---------------------------------------------------------------------------

resource "azurerm_cosmosdb_account" "this" {
  name                = "cosmos-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  public_network_access_enabled     = false
  is_virtual_network_filter_enabled = false
  local_authentication_disabled     = true # Entra ID (RBAC) auth only
  minimal_tls_version               = "Tls12"
  automatic_failover_enabled        = false

  consistency_policy {
    consistency_level = var.cosmos_consistency_level
  }

  geo_location {
    location          = azurerm_resource_group.this.location
    failover_priority = 0
  }

  dynamic "capabilities" {
    for_each = var.cosmos_serverless ? ["EnableServerless"] : []
    content {
      name = capabilities.value
    }
  }

  backup {
    type = "Continuous"
    tier = "Continuous7Days"
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_sql_database" "this" {
  name                = var.cosmos_database_name
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
}

resource "azurerm_cosmosdb_sql_container" "this" {
  for_each = var.cosmos_containers

  name                = each.key
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  database_name       = azurerm_cosmosdb_sql_database.this.name
  partition_key_paths = [each.value.partition_key_path]
}

# ---------------------------------------------------------------------------
# Private DNS + Private Endpoint
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "link-${azurerm_virtual_network.this.name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-${azurerm_cosmosdb_account.this.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${azurerm_cosmosdb_account.this.name}"
    private_connection_resource_id = azurerm_cosmosdb_account.this.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "cosmos-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos.id]
  }
}

# ---------------------------------------------------------------------------
# Data-plane RBAC (key auth is disabled, so identities need a role)
# ---------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_role_assignment" "data_contributor" {
  for_each = var.cosmos_data_contributor_principal_ids

  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  # Built-in "Cosmos DB Built-in Data Contributor"
  role_definition_id = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id       = each.value
  scope              = azurerm_cosmosdb_account.this.id
}
