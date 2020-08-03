variable "name" {}

variable "location" {
  default = "East US"
}

variable "aks_version" {
  default = "1.16.10"
}

locals {
  name_prefix = var.name
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-resources"
  location = var.location
}

# Create Azure Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-log-analytics-workspace"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Create AKS service principal
resource "azuread_application" "main" {
  name = "${local.name_prefix}-principal"
}

resource "azuread_service_principal" "main" {
  application_id = azuread_application.main.application_id
}

resource "random_string" "password" {
  length = 32
}

resource "azuread_service_principal_password" "main" {
  service_principal_id = azuread_service_principal.main.id
  value                = random_string.password.result
  end_date_relative    = "8760h"
}

# Create virtual network (VNet)
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-network"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.240.0.0/16"]
}

# Create AKS subnet to be used by nodes and pods
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.240.1.0/24"]
}

# Create Virtual Node (ACI) subnet
resource "azurerm_subnet" "aci" {
  name                 = "aci-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.240.2.0/24"]

  # Designate subnet to be used by ACI
  delegation {
    name = "aci-delegation"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Grant AKS cluster access to join AKS subnet
resource "azurerm_role_assignment" "aks_subnet" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.main.id
}

# Grant AKS cluster access to join ACI subnet
resource "azurerm_role_assignment" "aci_subnet" {
  scope                = azurerm_subnet.aci.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.main.id
}

# Create Kubernetes cluster (AKS)
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name_prefix}-cluster"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.name_prefix
  kubernetes_version  = var.aks_version

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = "Standard_DS2_v2"
    os_disk_size_gb = 30
    vnet_subnet_id  = azurerm_subnet.aks.id
  }

  addon_profile {
    # Enable virtual node (ACI connector) for Linux
    aci_connector_linux {
      enabled     = true
      subnet_name = azurerm_subnet.aci.name
    }
    # Enable Azure Monitor (Insights) for containers
    oms_agent {
      enabled     = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    }
  }

  network_profile {
    network_plugin = "azure"
  }

  role_based_access_control {
    enabled = true
  }

  service_principal {
    client_id     = azuread_application.main.application_id
    client_secret = azuread_service_principal_password.main.value
  }
}