SHOW CORTEX BASE MODELS
  ->> SELECT "name", "lifecycle_status",
             IFF(ARRAY_CONTAINS('AWS_AP_NORTHEAST_1'::VARIANT, "in_region_availability"), 'Y', '-') AS in_tokyo
      FROM $1 ORDER BY 1;
