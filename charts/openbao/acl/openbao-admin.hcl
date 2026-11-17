# OpenBao operators (not root): identity, ACL policies, auth methods, audit.
# Attached only via OIDC role "admin", not via identity groups, so a default
# EMBL-EBI login stays limited to catalog KV grants.

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["read", "list"]
}

path "sys/audit" {
  capabilities = ["read", "list", "sudo"]
}

path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/health" {
  capabilities = ["read", "sudo"]
}

path "sys/config/ui/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}
