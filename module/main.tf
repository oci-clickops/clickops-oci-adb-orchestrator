locals {
  # Extract ADB configuration following the orchestrator's pattern
  adbs_config = var.autonomous_databases_configuration != null ? var.autonomous_databases_configuration.autonomous_databases : {}

  # Default configuration
  default_compartment_id = var.autonomous_databases_configuration != null ? var.autonomous_databases_configuration.default_compartment_id : null
  default_defined_tags   = var.autonomous_databases_configuration != null ? try(var.autonomous_databases_configuration.default_defined_tags, {}) : {}
  default_freeform_tags  = var.autonomous_databases_configuration != null ? try(var.autonomous_databases_configuration.default_freeform_tags, {}) : {}

  # Process each ADB resolving dependencies
  processed_adbs = {
    for adb_key, adb in local.adbs_config : adb_key => merge(adb, {
      # Resolve compartment_id using dependencies or default
      compartment_id = try(adb.compartment_id, null) != null ? (
        can(regex("^ocid1.compartment.", adb.compartment_id)) ? adb.compartment_id : (
          var.compartments_dependency != null && contains(keys(var.compartments_dependency), adb.compartment_id) ? 
          var.compartments_dependency[adb.compartment_id].id : local.default_compartment_id
        )
      ) : local.default_compartment_id

      # Resolve subnet_id using network dependencies
      subnet_id = try(adb.subnet_id, null) != null ? (
        can(regex("^ocid1.subnet.", adb.subnet_id)) ? adb.subnet_id : (
          var.network_dependency != null && var.network_dependency.subnets != null && contains(keys(var.network_dependency.subnets), adb.subnet_id) ?
          var.network_dependency.subnets[adb.subnet_id].id : null
        )
      ) : null

      # Resolve NSGs using network dependencies
      nsg_ids = try(adb.nsg_ids, null) != null ? [
        for nsg in adb.nsg_ids : can(regex("^ocid1.networksecuritygroup.", nsg)) ? nsg : (
          var.network_dependency != null && var.network_dependency.network_security_groups != null && contains(keys(var.network_dependency.network_security_groups), nsg) ?
          var.network_dependency.network_security_groups[nsg].id : nsg
        )
      ] : []

      # Resolve KMS key using dependencies
      kms_key_id = try(adb.kms_key_id, null) != null ? (
        can(regex("^ocid1.key.", adb.kms_key_id)) ? adb.kms_key_id : (
          var.kms_dependency != null && contains(keys(var.kms_dependency), adb.kms_key_id) ?
          var.kms_dependency[adb.kms_key_id].id : null
        )
      ) : null

      # Merge tags
      defined_tags  = merge(local.default_defined_tags, try(adb.defined_tags, {}))
      freeform_tags = merge(local.default_freeform_tags, try(adb.freeform_tags, {}))

      # Display name
      display_name = try(adb.display_name, null) != null ? adb.display_name : adb.db_name
    })
  }
}

# Main resource for Autonomous Databases
resource "oci_database_autonomous_database" "autonomous_databases" {
  for_each = local.processed_adbs

  # Basic configuration
  compartment_id = each.value.compartment_id
  db_name        = each.value.db_name
  display_name   = each.value.display_name

  # Resource configuration - ONLY compute_count for ECPU
  compute_count            = try(each.value.cpu_core_count, 1)
  data_storage_size_in_tbs = try(each.value.data_storage_size_in_tbs, 1)
  compute_model            = try(each.value.compute_model, "ECPU")

  # Workload configuration
  db_workload = try(each.value.db_workload, "OLTP")
  db_version  = try(each.value.db_version, "19c")

  # Scaling configuration
  is_auto_scaling_enabled             = try(each.value.is_auto_scaling_enabled, false)
  is_auto_scaling_for_storage_enabled = try(each.value.is_auto_scaling_for_storage_enabled, false)

  # License configuration
  license_model = try(each.value.license_model, "BRING_YOUR_OWN_LICENSE")

  # Security configuration
  admin_password              = try(each.value.admin_password, null)
  is_mtls_connection_required = try(each.value.is_mtls_connection_required, false)
  kms_key_id                  = each.value.kms_key_id

  # Network configuration
  subnet_id              = each.value.subnet_id
  nsg_ids                = each.value.nsg_ids
  private_endpoint_label = try(each.value.private_endpoint_label, null)

  # Additional configuration
  is_free_tier = try(each.value.is_free_tier, false)
  is_dedicated = try(each.value.is_dedicated, false)

  # Tags
  defined_tags  = each.value.defined_tags
  freeform_tags = each.value.freeform_tags

  lifecycle {
    ignore_changes = [
      admin_password,
      defined_tags["Oracle-Tags.CreatedBy"],
      defined_tags["Oracle-Tags.CreatedOn"]
    ]
  }
}
