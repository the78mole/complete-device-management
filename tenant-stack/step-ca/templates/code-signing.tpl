{
    "subject": {
        "commonName": {{ toJson .Subject.CommonName }},
        "organization": ["CDM IoT Platform"],
        "organizationalUnit": ["Code Signing"]
    },
    "keyUsage": ["digitalSignature"],
    "extKeyUsage": ["codeSigning"],
    "basicConstraints": {
        "isCA": false
    }
}
