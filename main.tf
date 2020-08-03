module "us-eastus-1" {
  source = "./modules/multi-region"
  name   = "aks-eastus"
  location = "East US"
  providers = {
    azurerm = azurerm.us-eastus-1
  }
}
module "us-westus-1" {
  source = "./modules/multi-region"
  name   = "aks-westus"
  location = "West US"
  providers = {
    azurerm = azurerm.us-westus-1
  }
}