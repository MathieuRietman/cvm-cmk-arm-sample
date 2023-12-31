@description('Name of the Attestation provider. Must be between 3 and 24 characters in length and use numbers and lower-case letters only.')
param attestationProviderName string = uniqueString(resourceGroup().name)

@description('Location for all resources.')
param parLocation string = resourceGroup().location

param policySigningCertificates string = ''





var PolicySigningCertificates = {
  PolicySigningCertificates: {
    keys: [
      {
        kty: 'RSA'
        use: 'sig'
        x5c: [
          policySigningCertificates
        ]
      }
    ]
  }
}

param parTags object = {}

resource attestationProvider 'Microsoft.Attestation/attestationProviders@2021-06-01-preview' = {
  name: attestationProviderName
  tags: parTags
  location: parLocation
  properties: (empty(policySigningCertificates) ? json('{}') : PolicySigningCertificates)
}

output attestationName string = attestationProviderName
output attestationUri string = attestationProvider.properties.attestUri
