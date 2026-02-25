{
    "subject": {
        "commonName": {{ toJson .Subject.CommonName }},
        "organization": ["CDM IoT Platform"],
        "organizationalUnit": ["Devices"]
    },
    "sans": {{ toJson .SANs }},
    "keyUsage": ["digitalSignature"],
    "extKeyUsage": ["clientAuth"],
    "basicConstraints": {
        "isCA": false
    }
}
