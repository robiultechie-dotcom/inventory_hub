# frozen_string_literal: true

class AddFullTextSearchIndexes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_inventories_on_fts_vector
      ON inventories
      USING gin (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(description, '')));
    SQL

    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_items_on_fts_vector
      ON items
      USING gin (to_tsvector('simple',
        coalesce(custom_id, '') || ' ' ||
        coalesce(custom_string1_val, '') || ' ' ||
        coalesce(custom_string2_val, '') || ' ' ||
        coalesce(custom_string3_val, '') || ' ' ||
        coalesce(custom_text1_val, '') || ' ' ||
        coalesce(custom_text2_val, '') || ' ' ||
        coalesce(custom_text3_val, '')
      ));
    SQL

    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_tags_on_fts_vector
      ON tags
      USING gin (to_tsvector('simple', coalesce(name, '')));
    SQL

    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_comments_on_fts_vector
      ON comments
      USING gin (to_tsvector('simple', coalesce(body, '')));
    SQL

    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_item_field_values_on_fts_vector
      ON item_field_values
      USING gin (to_tsvector('simple', coalesce(string_value, '') || ' ' || coalesce(text_value, '')));
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_item_field_values_on_fts_vector;"
    execute "DROP INDEX IF EXISTS index_comments_on_fts_vector;"
    execute "DROP INDEX IF EXISTS index_tags_on_fts_vector;"
    execute "DROP INDEX IF EXISTS index_items_on_fts_vector;"
    execute "DROP INDEX IF EXISTS index_inventories_on_fts_vector;"
  end
end