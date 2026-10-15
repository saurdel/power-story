output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "app_subnet_id" {
  description = "Deploy workloads (VMs, App Service VNet integration, AKS, etc.) into this subnet."
  value       = azurerm_subnet.app.id
}

output "cosmos_account_name" {
  value = azurerm_cosmosdb_account.this.name
}

output "cosmos_endpoint" {
  description = "Resolves to the private endpoint IP from inside the VNet."
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "cosmos_private_ip" {
  value = azurerm_private_endpoint.cosmos.private_service_connection[0].private_ip_address
}

output "cosmos_database_name" {
  value = azurerm_cosmosdb_sql_database.this.name
}
