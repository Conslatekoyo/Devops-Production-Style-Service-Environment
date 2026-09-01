output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "codebuild_projects" {
  value = {
    booking  = aws_codebuild_project.booking.name
    driver   = aws_codebuild_project.driver.name
    tracking = aws_codebuild_project.tracking.name
  }
}

output "pipelines" {
  value = {
    for key, pipeline in aws_codepipeline.service :
    key => pipeline.name
  }
}

output "codepipeline_role_arn" {
  value = aws_iam_role.codepipeline.arn
}

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild.arn
}
