{
    "subject": {
        "commonName": {{ toJson .Subject.CommonName }},
        "organization": ["CDM IoT Platform"],
        "organizationalUnit": ["Services"]
    },
    "sans": {{ toJson .SANs }},
    "keyUsage": ["digitalSignature", "keyEncipherment"],
    "extKeyUsage": ["serverAuth", "clientAuth"],
    "basicConstraints": {
        "isCA": false
    }
}
