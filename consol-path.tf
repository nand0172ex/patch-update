# -------------------------
# VARIABLES (Define in variables.tf or elsewhere)
# -------------------------
variable "ssm_automation_role_arn" {
  description = "IAM Role ARN for SSM Maintenance Window"
  type        = string
}

# -------------------------
# SSM DOCUMENT: CheckPatchStatus
# -------------------------
resource "aws_ssm_document" "check_patch_status" {
  name          = "CheckPatchStatus-RHEL8"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2",
    description   = "Check Patch Status on RHEL 8",
    mainSteps = [{
      action = "aws:runShellScript",
      name   = "checkpatch",
      inputs = {
        runCommand = [
          "echo '[Step 2] Verifying patch status...'",
          "dnf updateinfo list installed || echo 'No updateinfo plugin installed or no updates applied.'"
        ]
      }
    }]
  })
}

# -------------------------
# SSM DOCUMENT: CheckRebootNeeded
# -------------------------
resource "aws_ssm_document" "check_reboot_needed" {
  name          = "CheckRebootNeeded-RHEL8"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2",
    description   = "Check if Reboot is Needed on RHEL 8",
    mainSteps = [{
      action = "aws:runShellScript",
      name   = "rebootcheck",
      inputs = {
        runCommand = [
          "echo '[Step 3] Checking if reboot is required (but not rebooting)...'",
          "dnf install -y dnf-utils || echo 'dnf-utils already installed'",
          "if dnf needs-restarting -r; then",
          "  echo '🔴 Reboot required - Manual reboot advised after testing.' | tee -a /var/log/patch-check.log",
          "else",
          "  echo '✅ No reboot needed.' | tee -a /var/log/patch-check.log",
          "fi"
        ]
      }
    }]
  })
}

# -------------------------
# MAINTENANCE WINDOW
# -------------------------
resource "aws_ssm_maintenance_window" "patch_window" {
  name     = "RHEL8PatchWindow"
  schedule = "cron(0 3 ? * SUN *)"  # Every Sunday 3 AM UTC
  duration = 3
  cutoff   = 1
}

# -------------------------
# MAINTENANCE WINDOW TARGET
# -------------------------
resource "aws_ssm_maintenance_window_target" "target" {
  window_id     = aws_ssm_maintenance_window.patch_window.id
  resource_type = "INSTANCE"
  targets = [{
    Key    = "tag:PatchGroup",
    Values = ["rhel8-nodes"]
  }]
}

# -------------------------
# TASK 1: RunPatchBaseline
# -------------------------
resource "aws_ssm_maintenance_window_task" "patch_task" {
  window_id        = aws_ssm_maintenance_window.patch_window.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  max_concurrency  = "2"
  max_errors       = "1"
  service_role_arn = var.ssm_automation_role_arn

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.target.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["NoReboot"]
      }
    }
  }

  name = "RunPatchBaselineTask"
}

# -------------------------
# TASK 2: Check Patch Status
# -------------------------
resource "aws_ssm_maintenance_window_task" "check_patch_task" {
  window_id        = aws_ssm_maintenance_window.patch_window.id
  task_type        = "RUN_COMMAND"
  task_arn         = aws_ssm_document.check_patch_status.arn
  priority         = 2
  max_concurrency  = "2"
  max_errors       = "1"
  service_role_arn = var.ssm_automation_role_arn

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.target.id]
  }

  name = "CheckPatchStatusTask"
}

# -------------------------
# TASK 3: Check Reboot Needed
# -------------------------
resource "aws_ssm_maintenance_window_task" "check_reboot_task" {
  window_id        = aws_ssm_maintenance_window.patch_window.id
  task_type        = "RUN_COMMAND"
  task_arn         = aws_ssm_document.check_reboot_needed.arn
  priority         = 3
  max_concurrency  = "2"
  max_errors       = "1"
  service_role_arn = var.ssm_automation_role_arn

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.target.id]
  }

  name = "CheckRebootNeededTask"
}
