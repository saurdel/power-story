variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "prefix" {
  description = "Short name prefix applied to all resources (lowercase letters and digits)."
  type        = string
  default     = "powerstory"

  validation {
    condition     = can(regex("^[a-z0-9]{3,20}$", var.prefix))
    error_message = "prefix must be 3-20 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "vnet_address_space" {
  description = "Address space of the virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "app_subnet_prefix" {
  description = "CIDR for the workload/app subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_endpoint_subnet_prefix" {
  description = "CIDR for the private endpoint subnet."
  type        = string
  default     = "10.20.2.0/24"
}

variable "cosmos_consistency_level" {
  description = "Cosmos DB default consistency level."
  type        = string
  default     = "Session"
}

variable "cosmos_serverless" {
  description = "Use serverless capacity mode instead of provisioned throughput."
  type        = bool
  default     = true
}

variable "cosmos_database_name" {
  description = "Name of the SQL database to create."
  type        = string
  default     = "appdb"
}

variable "cosmos_containers" {
  description = "SQL containers to create, keyed by name, with their partition key path."
  type = map(object({
    partition_key_path = string
  }))
  default = {
    items = { partition_key_path = "/id" }
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project = "power-story"
    managed = "terraform"
  }
}

variable "cosmos_data_contributor_principal_ids" {
  description = "Entra ID object IDs (e.g. app managed identities) granted Cosmos DB Built-in Data Contributor."
  type        = set(string)
  default     = []
}
