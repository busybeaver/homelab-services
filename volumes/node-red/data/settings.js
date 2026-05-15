module.exports = {
    uiPort: 443,
    https: {
        key: require("fs").readFileSync("/cert/cert.key"),
        cert: require("fs").readFileSync("/cert/cert.cer")
    },
    credentialSecret: "dummy-secret-for-ci",
    adminAuth: {
        type: "credentials",
        users: []
    }
}
