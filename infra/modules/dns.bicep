// =============================================================================
// Module: dns.bicep
// =============================================================================
// Provisions a public Azure DNS zone for the Zava A2A demo. The AKS Application
// Routing add-on identity is granted DNS Zone Contributor on this zone (in
// identity.bicep) so it can create A/CNAME records for the Ops Agent ingress.
//
// Resource: Microsoft.Network/dnsZones
// API:      2023-07-01-preview (current GA-equivalent for public zones)
//   - Public DNS zones are created at the special location 'global'.
//
// Configuration (per plan §C Step 7):
//   - The zone name has no default — the deployer must pass a domain they
//     control (or a placeholder for compile-only validation), then delegate
//     it by configuring the registrar to use the NS records this module
//     emits as outputs.
//
// References:
//   - plan.md §C Step 7
//   - https://learn.microsoft.com/azure/dns/dns-zones-records
// =============================================================================

@description('Fully-qualified DNS zone name (e.g., "zava-demo.example.com"). The deployer must own/control this zone or accept that delegation is a manual post-deploy step.')
param dnsZoneName string

@description('Tags applied to the DNS zone.')
param tags object = {}

resource dnsZone 'Microsoft.Network/dnsZones@2023-07-01-preview' = {
  name: dnsZoneName
  // Public DNS zones must be deployed at location 'global'.
  location: 'global'
  tags: tags
  properties: {
    zoneType: 'Public'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('DNS zone ARM resource ID — used as scope for the DNS Zone Contributor role assignment in identity.bicep.')
output dnsZoneId string = dnsZone.id

@description('DNS zone name (echoed back for downstream modules and ingress host configuration).')
output dnsZoneName string = dnsZone.name

@description('Azure-assigned authoritative name servers for this zone. The deployer configures these at the domain registrar to delegate the zone.')
output dnsZoneNameServers array = dnsZone.properties.nameServers
