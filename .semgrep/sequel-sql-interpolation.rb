# ruleid: sequel-sql-interpolation
Sequel.lit("metadata->>'#{key}'")

# ruleid: sequel-sql-interpolation
DB.run("DELETE FROM works WHERE id = #{id}")

# ruleid: sequel-sql-interpolation
DB["SELECT * FROM works WHERE title = '#{title}'"]

# ruleid: sequel-sql-interpolation
works.where("title = '#{title}'")

# ok: sequel-sql-interpolation
Sequel.lit('title = ?', title)

# ok: sequel-sql-interpolation
works.where(title: title)

# ok: sequel-sql-interpolation
Sequel.pg_jsonb_op(:metadata).get_text(key)
