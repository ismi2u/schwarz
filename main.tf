# Configure the Microsoft Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}
provider "azurerm" {
  features {}
}

# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "schwarz" {
  name     = "schwarz_rg"
  location = "east us 2"

  tags = {
    environment = "development"
  }
}

# Create virtual network
resource "azurerm_virtual_network" "schwarz" {
  name                = "schwarz_vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.schwarz.location
  resource_group_name = azurerm_resource_group.schwarz.name

  tags = {
    environment = "development"
  }
}

# Create subnet
resource "azurerm_subnet" "schwarz" {
  name                 = "schwarz_subnet"
  resource_group_name  = azurerm_resource_group.schwarz.name
  virtual_network_name = azurerm_virtual_network.schwarz.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "schwarz" {
  name                = "schwarz_publicip"
  location            = azurerm_resource_group.schwarz.location
  resource_group_name = azurerm_resource_group.schwarz.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "development"
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "schwarz" {
  name                = "schwarz_nsg"
  location            = azurerm_resource_group.schwarz.location
  resource_group_name = azurerm_resource_group.schwarz.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "development"
  }
}

# Create network interface
resource "azurerm_network_interface" "schwarz" {
  name                = "schwarz_nic"
  location            = azurerm_resource_group.schwarz.location
  resource_group_name = azurerm_resource_group.schwarz.name

  ip_configuration {
    name                          = "myNicConfiguration"
    subnet_id                     = azurerm_subnet.schwarz.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.schwarz.id
  }

  tags = {
    environment = "development"
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "schwarz" {
  network_interface_id      = azurerm_network_interface.schwarz.id
  network_security_group_id = azurerm_network_security_group.schwarz.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.schwarz.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "schwarz" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = azurerm_resource_group.schwarz.name
  location                 = azurerm_resource_group.schwarz.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "development"
  }
}

# Create (and display) an SSH key
resource "tls_private_key" "schwarz" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
output "tls_private_key" {
  value     = tls_private_key.schwarz.private_key_pem
  sensitive = true
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "schwarz" {
  name                  = "schwarzdevm"
  location              = azurerm_resource_group.schwarz.location
  resource_group_name   = azurerm_resource_group.schwarz.name
  network_interface_ids = [azurerm_network_interface.schwarz.id]
  size                  = "Standard_B1s"
  #   size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "schwarz_osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-LTS"
    version   = "latest"
  }


  resource "azurerm_virtual_machine_extension" "schwarz" {
    name                 = "schwarzdevm"
    virtual_machine_id   = azurerm_linux_virtual_machine.schwarz.id
    publisher            = "Microsoft.Azure.Extensions"
    type                 = "CustomScript"
    type_handler_version = "2.0"

    settings = <<SETTINGS
    {
        "commandToExecute": "hostname && uptime"
    }
SETTINGS


    tags = {
      environment = "development"
    }
  }




  computer_name                   = "schwarzdevvm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.schwarz.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.schwarz.primary_blob_endpoint
  }

  tags = {
    environment = "development"
  }
}
