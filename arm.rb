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

def create_storage_profile(storage_client, resource_group)
  storage_profile = StorageProfile.new
  storage_profile.image_reference = get_image_reference
  storage = create_storage_account(storage_client, resource_group)
  os_disk = OSDisk.new
  os_disk.caching = 'None'
  os_disk.create_option = 'fromImage'
  os_disk.name = 'Test'
  virtual_hard_disk = VirtualHardDisk.new
  virtual_hard_disk.uri = generate_os_vhd_uri storage.name
  os_disk.vhd = virtual_hard_disk
  storage_profile.os_disk = os_disk
  storage_profile
end

def generate_os_vhd_uri(storage_name)
  container_name = 'cont-' + TEST_NAME
  vhd_container = "https://#{storage_name}.blob.core.windows.net/#{container_name}"
  os_vhduri = "#{vhd_container}/#{TEST_NAME}.vhd"
  os_vhduri
end

def get_image_reference
  ref = ImageReference.new
  ref.publisher = 'Canonical'
  ref.offer = 'UbuntuServer'
  ref.sku = '14.04.3-LTS'
  ref.version = 'latest'
  ref
end

def create_storage_account(storage_client, resource_group)
  storage_name = 'storage' + TEST_NAME
  params = build_storage_account_create_parameters(storage_name, resource_group.location)
  result = storage_client.storage_accounts.create(resource_group.name, storage_name, params).value!.body
  result.name = storage_name #similar problem in dot net tests
  result
end

def build_storage_account_create_parameters(name, location)
  params = Azure::ARM::Storage::Models::StorageAccountCreateParameters.new
  params.location = location
  params.name = name
  props = Azure::ARM::Storage::Models::StorageAccountPropertiesCreateParameters.new
  params.properties = props
  props.account_type = 'Standard_GRS'
  params
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
  network_interface_name = 'nic-' + TEST_NAME
  ip_configuration = create_ip_configuration(network_client, resource_group, subnet)
  nsg = create_network_security_group(network_client, resource_group)
  props = NetworkInterfacePropertiesFormat.new
  props.ip_configurations = [ip_configuration]
  props.network_security_group = nsg
  params = NetworkInterface.new
  params.location = resource_group.location
  params.name = network_interface_name
  params.properties = props
  params
end

def create_network_security_group(network_client, resource_group)
  sr_props = SecurityRulePropertiesFormat.new
  sr_props.priority = 100
  sr_props.source_port_range = '1-65000'
  sr_props.destination_port_range = '1-65000'
  sr_props.source_address_prefix = '*'
  sr_props.destination_address_prefix = '*'
  sr_props.protocol = 'Tcp' # 'Udp' or '*'
  sr_props.access = 'Deny'
  sr_props.direction = 'Inbound' # 'Outbound'
  sr = SecurityRule.new
  sr.properties = sr_props
  sr.name = "sr-#{TEST_NAME}"
  props = NetworkSecurityGroupPropertiesFormat.new
  props.security_rules = [sr]
  nsg = NetworkSecurityGroup.new
  nsg.properties = props
  nsg.location = resource_group.location
  nsg = network_client.network_security_groups.create_or_update(resource_group.name, resource_group.name, nsg).value!.body
  # create_security_rules(network_client, nsg, resource_group)
  nsg
end

def update_security_group(network_client, nsg)
  sr_props = SecurityRulePropertiesFormat.new
  sr_props.priority = 100
  sr_props.source_port_range = '1-65000'
  sr_props.destination_port_range = '1-65000'
  sr_props.source_address_prefix = '*'
  sr_props.destination_address_prefix = '*'
  sr_props.protocol = 'Tcp' # 'Udp' or '*'
  sr_props.access = 'Allow'
  sr_props.direction = 'Inbound' # 'Outbound'
  sr = SecurityRule.new
  sr.properties = sr_props
  sr.name = "sr-#{TEST_NAME}"
  nsg.properties.security_rules = [sr]
  name = TEST_NAME
  network_client.network_security_groups.create_or_update(name, name, nsg).value!.body
end

def create_security_rules(network_client, security_group, resource_group)
  props = SecurityRulePropertiesFormat.new
  props.priority = 100
  props.source_port_range = '1-65000'
  props.destination_port_range = '1-65000'
  props.source_address_prefix = '*'
  props.destination_address_prefix = '*'
  props.protocol = 'Tcp' # 'Udp' or '*'
  props.access = 'Deny'
  props.direction = 'Inbound' # 'Outbound'
  sr = SecurityRule.new
  sr.properties = props
  sr.name = "sr-#{TEST_NAME}"
  network_client.security_rules.create_or_update(resource_group.name, security_group.name, sr.name, sr).value!.body
end

def create_ip_configuration(network_client, resource_group, subnet)
  puts "     - creating ip"
  ip_configuration = NetworkInterfaceIpConfiguration.new
  ip_configuration_properties = NetworkInterfaceIpConfigurationPropertiesFormat.new
  ip_configuration.properties = ip_configuration_properties
  ip_configuration.name = 'ip_name-' + TEST_NAME
  ip_configuration_properties.private_ipallocation_method = 'Dynamic'
  ip_configuration_properties.public_ipaddress = create_public_ip_address(network_client, resource_group)
  ip_configuration_properties.subnet = subnet
  ip_configuration
end

def build_public_ip_params(location)
  public_ip = PublicIpAddress.new
  public_ip.location = location
  props = PublicIpAddressPropertiesFormat.new
  props.public_ipallocation_method = 'Dynamic'
  domain_name = 'domain-' + TEST_NAME
  # dns_settings = PublicIpAddressDnsSettings.new
  # dns_settings.domain_name_label = domain_name
  # props.dns_settings = dns_settings
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

def get_virtual_machine(compute_client, resource_group_name, vm_name)
  compute_client.virtual_machines.get(resource_group_name, vm_name, 'instanceView').value!.body
end

def create_virtual_machine(compute_client, network_client, storage_client, resource_group)
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
  puts " * building storage profile"
  props.storage_profile = create_storage_profile(storage_client, resource_group)
  params = VirtualMachine.new
  params.type = 'Microsoft.Compute/virtualMachines'
  params.properties = props
  params.location = resource_group.location
  puts " * deploying VM"
  promise = compute_client.virtual_machines.create_or_update(TEST_NAME, TEST_NAME, params)
  result = promise.value!
  result.body
end

def resource_group_exists?(resources_client, rg_name)
  promise = resources_client.resource_groups.check_existence(rg_name)
  result = promise.value!
  resource_group = result.body
end

def resource_group_delete(resources_client, rg_name)
  promise = resources_client.resource_groups.delete(rg_name)
  result = promise.value!
  result.body
end

def get_ip_address(network_client, name)
  network_client.public_ip_addresses.get(name, 'ip-' + name)
end

def get_security_rules(network_client, name)
  network_client.security_rules.list(name, name).value!.body
end

def get_security_group(network_client, name)
  network_client.network_security_groups.get(name, name).value!.body
end

def get_inex_security_group(network_client, name)
  network_client.network_security_groups.get(name, name+'-nonexisting').value!.body
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
  puts " * Response (#{list.count} vms) : #{list}"

  # puts "Deleting all (#{list.count}) vms in the subscription..." unless list.empty?
  # # Delete the resource group, and all other resources will be deleted on cascade
  # list.each do |vm|
  #   promise = resources_client.resource_groups.delete(vm.name)
  #   result = promise.value!
  #   puts " * Deleted #{vm.name} : #{result.body}"
  # end

  puts "Checking existence of resource group named '#{TEST_NAME}' ..."
  rgpresent = resource_group_exists?(resources_client, TEST_NAME)
  puts " * Resource group '#{TEST_NAME}'#{rgpresent ? '' : ' not'} present"

  if rgpresent
    puts "Deleting resource group named '#{TEST_NAME}' ..."
    resource_group_delete(resources_client, TEST_NAME)
    puts " * Resource group #{TEST_NAME} deleted"
  end

  puts "Creating a resource group named '#{TEST_NAME}' ..."
  resource_group = Azure::ARM::Resources::Models::ResourceGroup.new()
  resource_group.location = LOCATION
  promise = resources_client.resource_groups.create_or_update(TEST_NAME, resource_group)
  result = promise.value!
  resource_group = result.body
  puts " * Created #{resource_group.name} with id '#{resource_group.id}' (#{resource_group.location})"

  puts "Creating a virtual machine named '#{TEST_NAME}' ..."
  vm = create_virtual_machine(compute_client, network_client, storage_client, resource_group)
  puts " * Created #{vm.name} with id : '#{vm.id}'"

  puts "Getting a virtual machine named '#{TEST_NAME}' ..."
  vm = get_virtual_machine(compute_client, TEST_NAME, TEST_NAME)
  puts " * Got #{vm} with id : '#{vm.id}'"

  puts "Getting assigned public ip address for virtual machine named '#{TEST_NAME}' ..."
  ip = get_ip_address(network_client, TEST_NAME)
  puts " * Got #{ip}"

  puts "Getting security rules for virtual machine named '#{TEST_NAME}' ..."
  srs = get_security_rules(network_client, TEST_NAME)
  puts " * Got #{srs}"

  puts "Getting security group for virtual machine named '#{TEST_NAME}' ..."
  nsg = get_security_group(network_client, TEST_NAME)
  puts " * Got #{nsg}"

  puts "Updating security group for virtual machine named '#{TEST_NAME}' ..."
  unsg = update_security_group(network_client, nsg)
  puts " * Got #{unsg}"  

  # puts "Getting inexistent security group for virtual machine named '#{TEST_NAME}' ..."
  # nensg = get_inex_security_group(network_client, TEST_NAME)
  # puts " * Got #{nensg}"

rescue MsRestAzure::AzureOperationError => ex
  puts "MsRestAzure::AzureOperationError : "
  puts " * request: #{ex.request}"
  puts " * response: #{ex.response}"
  puts " * body: #{ex.body}"
  puts ex
end
