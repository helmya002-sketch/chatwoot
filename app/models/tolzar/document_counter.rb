# Tolzar booking documents: the last number issued per workspace, type and year (row-locked by Tolzar::Document#issue!).
class Tolzar::DocumentCounter < ApplicationRecord
  self.table_name = 'tolzar_document_counters'
end
