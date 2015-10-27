require 'azure_mgmt_compute'
require 'azure_mgmt_resources'
require 'azure_mgmt_storage'
require 'azure_mgmt_network'

# Include SDK modules to ease access to classes
include Azure::ARM::Resources
include Azure::ARM::Resources::Models
include Azure::ARM::Compute
include Azure::ARM::Compute::Models
include Azure::ARM::Network
include Azure::ARM::Network::Models
include Azure::ARM::Storage
include Azure::ARM::Storage::Models

LOCATION  = 'westeurope'
TEST_NAME = 'ohmytest'

tenant_id       = ENV['ARM_TENANT_ID']
client_id       = ENV['ARM_CLIENT_ID']
secret          = ENV['ARM_SECRET']
subscription_id = ENV['ARM_SUBSCRIPTION_ID']

def authenticate(tenant_id, client_id, secret)
  token_provider = MsRestAzure::ApplicationTokenProvider.new(tenant_id, client_id, secret)
  credentials = MsRest::TokenCredentials.new(token_provider)
end

def create_storage_profile
  raise NotImplementedError
end

def create_network_profile(network_client, resource_group)
  puts "   + creating virtual network"
  vn = create_virtual_network(network_client, resource_group)
  puts "   + creating subnet"
  subnet = create_subnet(vn, resource_group, network_client.subnets)
  puts "   + creating network interface"
  network_interface = create_network_interface(network_client, resource_group, subnet)

  puts "   + done"
  profile = NetworkProfile.new
  profile.network_interfaces = [network_interface]
  profile
end

def build_subnet_params
  params = Subnet.new
  prop = SubnetPropertiesFormat.new
  params.properties = prop
  prop.address_prefix = '10.0.1.0/24'
  params
end

def create_subnet(virtual_network, resource_group, subnet_client)
  subnet_name = 'subnet-' + TEST_NAME
  params = build_subnet_params
  subnet_client.create_or_update(resource_group.name, virtual_network.name, subnet_name, params).value!.body
end

def create_network_interface(network_client, resource_group, subnet)
  params = build_network_interface_param(network_client, resource_group, subnet)
  network_client.network_interfaces.create_or_update(resource_group.name, params.name, params).value!.body
end

def build_network_interface_param(network_client, resource_group, subnet)
  puts "     - building params"
  params = NetworkInterface.new
  params.location = resource_group.location
  network_interface_name = 'nic-' + TEST_NAME
  ip_config_name = 'ip_name-' + TEST_NAME
  params.name = network_interface_name
  props = NetworkInterfacePropertiesFormat.new
  ip_configuration = NetworkInterfaceIpConfiguration.new
  params.properties = props
  props.ip_configurations = [ip_configuration]
  ip_configuration_properties = NetworkInterfaceIpConfigurationPropertiesFormat.new
  ip_configuration.properties = ip_configuration_properties
  ip_configuration.name = ip_config_name
  ip_configuration_properties.private_ipallocation_method = 'Dynamic'
  puts "     - creating public ip"
  ip_configuration_properties.public_ipaddress = create_public_ip_address(network_client, resource_group)
  puts "     - done"
  ip_configuration_properties.subnet = subnet
  params
end

def build_public_ip_params(location)
  puts "     --- #{location}"
  public_ip = PublicIpAddress.new
  public_ip.location = location
  props = PublicIpAddressPropertiesFormat.new
  props.public_ipallocation_method = 'Dynamic'
  domain_name = 'domain-' + TEST_NAME
  dns_settings = PublicIpAddressDnsSettings.new
  dns_settings.domain_name_label = domain_name
  props.dns_settings = dns_settings
  public_ip.properties = props
  public_ip
end

def create_public_ip_address(network_client, resource_group)
  public_ip_address_name = 'ip_name' + TEST_NAME
  params = build_public_ip_params(resource_group.location)
  network_client.public_ip_addresses.create_or_update(resource_group.name, public_ip_address_name, params).value!.body
end

def build_virtual_network_params(location)
  params = VirtualNetwork.new
  props = VirtualNetworkPropertiesFormat.new
  params.location = location
  address_space = AddressSpace.new
  address_space.address_prefixes = ['10.0.0.0/16']
  props.address_space = address_space
  # dhcp_options = DhcpOptions.new
  # dhcp_options.dns_servers = %w(10.1.1.1 10.1.2.4)
  # props.dhcp_options = dhcp_options
  # sub2 = Subnet.new
  # sub2_prop = SubnetPropertiesFormat.new
  # sub2.name = "subnet-#{TEST_NAME}"
  # sub2_prop.address_prefix = '10.0.2.0/24'
  # sub2.properties = sub2_prop
  # props.subnets = [sub2]
  params.properties = props
  params
end

def create_virtual_network(network_client, resource_group)
  virtualNetworkName = "vnet-#{TEST_NAME}"
  params = build_virtual_network_params(resource_group.location)
  network_client.virtual_networks.create_or_update(resource_group.name, virtualNetworkName, params).value!.body
end

def create_virtual_machine(compute_client, network_client, resource_group)
  puts " * building OS profile"
  os_profile = OSProfile.new
  os_profile.computer_name = TEST_NAME
  os_profile.admin_username = TEST_NAME
  os_profile.admin_password = 'P@ssword1'
  puts " * building hardware profile"
  hardware_profile = HardwareProfile.new
  hardware_profile.vm_size = 'Standard_A0'
  props = VirtualMachineProperties.new
  props.os_profile = os_profile
  props.hardware_profile = hardware_profile
  puts " * building network profile"
  props.network_profile = create_network_profile(network_client, resource_group)
  # puts " * building storage profile"
  # props.storage_profile = create_storage_profile
  params = VirtualMachine.new
  params.type = 'Microsoft.Compute/virtualMachines'
  params.properties = props
  params.location = resource_group.location
  promise = compute_client.virtual_machines.create_or_update(TEST_NAME, TEST_NAME, params)
  result = promise.value!
  result.body
end

begin
  puts "Azure ARM. Authenticating with params: tenant_id: #{tenant_id} , client_id: #{client_id} , secret: #{secret}"
  credentials = authenticate(tenant_id, client_id, secret)
  puts "Got credentials: #{credentials.to_s}"

  # Create a compute client
  compute_client = ComputeManagementClient.new(credentials)
  compute_client.subscription_id = subscription_id
  # Create a resources client
  resources_client = ResourceManagementClient.new(credentials)
  resources_client.subscription_id = subscription_id
  # Create a storage client
  storage_client = StorageManagementClient.new(credentials)
  storage_client.subscription_id = subscription_id
  # Create a network client
  network_client = NetworkResourceProviderClient.new(credentials)
  network_client.subscription_id = subscription_id

  puts "List all vms in the subscription..."
  promise = compute_client.virtual_machines.list_all
  result = promise.value!
  list = result.body.value
  puts " * Response (#{list.count} vms) : #{list.map(&:name)}"

  puts "Deleting all (#{list.count}) vms in the subscription..." unless list.empty?
  # Delete the resource group, and all other resources will be deleted on cascade
  list.each do |vm|
    promise = resources_client.resource_groups.delete(vm.name)
    result = promise.value!
    puts " * Deleted #{vm.name} : #{result.body}"
  end

  puts "Creating a resource group named '#{TEST_NAME}' ..."
  resource_group = Azure::ARM::Resources::Models::ResourceGroup.new()
  resource_group.location = LOCATION
  promise = resources_client.resource_groups.create_or_update(TEST_NAME, resource_group)
  result = promise.value!
  resource_group = result.body
  puts " * Created #{resource_group.name} with id '#{resource_group.id}' (#{resource_group.location})"

  puts "Creating a virtual machine named '#{TEST_NAME}' ..."
  vm = create_virtual_machine(compute_client, network_client, resource_group)
  puts " * Created #{vm.name} with id : '#{vm.id}'"




rescue MsRestAzure::AzureOperationError => ex
  puts "MsRestAzure::AzureOperationError : "
  puts " * request: #{ex.request}"
  puts " * response: #{ex.response}"
  puts " * body: #{ex.body}"
end
