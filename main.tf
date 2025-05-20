resource "aws_ssm_document" "rhel8_patch_lifecycle" {
  name          = "RHEL8SafePatchLifecycle"
  document_type = "Automation"
  content       = file("documents/rhel8-safe-patch.json")
}

resource "aws_ssm_maintenance_window" "rhel8_patch_window" {
  name     = "RHEL8PatchWindow"
  schedule = "cron(0 3 ? * SUN *)" # Every Sunday 3 AM UTC
  duration = 2
  cutoff   = 1
}

resource "aws_ssm_maintenance_window_target" "rhel8_patch_target" {
  window_id     = aws_ssm_maintenance_window.rhel8_patch_window.id
  resource_type = "INSTANCE"
  targets = [{
    Key    = "tag:PatchGroup"
    Values = ["rhel8-nodes"]
  }]
}

resource "aws_ssm_maintenance_window_task" "rhel8_patch_task" {
  window_id        = aws_ssm_maintenance_window.rhel8_patch_window.id
  task_arn         = aws_ssm_document.rhel8_patch_lifecycle.arn
  task_type        = "AUTOMATION"
  priority         = 1
  max_concurrency  = "2"
  max_errors       = "1"
  service_role_arn = var.ssm_automation_role_arn

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.rhel8_patch_target.id]
  }

  task_invocation_parameters {
    automation_parameters {
      document_version = "$LATEST"
    }
  }

  name = "RHEL8PatchLifecycleTask"
}
