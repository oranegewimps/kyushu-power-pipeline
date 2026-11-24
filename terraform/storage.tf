# 取得した CSV をそのまま保存する場所（あとから再処理・監査できるように）
resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-raw"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # 公表値が後から修正されて同じ名前で上書きしても、修正前の版が残るようにする
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  depends_on = [google_project_service.apis]
}
