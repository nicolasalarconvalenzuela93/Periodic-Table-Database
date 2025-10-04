#!/bin/bash
# Project: periodic_table CLI — small fixes
# This file is used by the freeCodeCamp exercise. Keep queries and trimming behaviour compatible with the tests.
PSQL="psql -X --username=freecodecamp --dbname=periodic_table --tuples-only -A -c"

MAIN_PROGRAM() {
  if [[ -z $1 ]]
  then
    echo "Please provide an element as an argument."
  else
    PRINT_ELEMENT $1
  fi
}

PRINT_ELEMENT() {
  INPUT=$1
  if [[ ! $INPUT =~ ^[0-9]+$ ]]
  then
    ATOMIC_NUMBER=$(echo $($PSQL "SELECT atomic_number FROM elements WHERE symbol='$INPUT' OR name='$INPUT';") | sed 's/ //g')
  else
    ATOMIC_NUMBER=$(echo $($PSQL "SELECT atomic_number FROM elements WHERE atomic_number=$INPUT;") | sed 's/ //g')
  fi
  
    if [[ -z $ATOMIC_NUMBER ]]
  then
    echo "I could not find that element in the database."
  else
    TYPE_ID=$($PSQL "SELECT type_id FROM properties WHERE atomic_number=$ATOMIC_NUMBER;" | sed -e 's/^ *//' -e 's/ *$//')
    NAME=$($PSQL "SELECT name FROM elements WHERE atomic_number=$ATOMIC_NUMBER;" | sed -e 's/^ *//' -e 's/ *$//')
    SYMBOL=$($PSQL "SELECT symbol FROM elements WHERE atomic_number=$ATOMIC_NUMBER;" | sed -e 's/^ *//' -e 's/ *$//')
    ATOMIC_MASS=$($PSQL "SELECT atomic_mass FROM properties WHERE atomic_number=$ATOMIC_NUMBER;" | sed -e 's/^ *//' -e 's/ *$//')
    MELTING_POINT_CELSIUS=$($PSQL "SELECT melting_point_celsius FROM properties WHERE atomic_number=$ATOMIC_NUMBER;" | sed -e 's/^ *//' -e 's/ *$//')
    BOILING_POINT_CELSIUS=$($PSQL "SELECT boiling_point_celsius FROM properties WHERE atomic_number=$ATOMIC_NUMBER;" | sed -e 's/^ *//' -e 's/ *$//')
    TYPE=$($PSQL "SELECT type FROM elements LEFT JOIN properties USING(atomic_number) LEFT JOIN types USING(type_id) WHERE atomic_number=$ATOMIC_NUMBER;" | sed -e 's/^ *//' -e 's/ *$//')

    echo "The element with atomic number $ATOMIC_NUMBER is $NAME ($SYMBOL). It's a $TYPE, with a mass of $ATOMIC_MASS amu. $NAME has a melting point of $MELTING_POINT_CELSIUS celsius and a boiling point of $BOILING_POINT_CELSIUS celsius."
  fi
}

FIX_DB() {
  # Rename weight -> atomic_mass
  RENAME_PROPERTIES_WEIGHT=$($PSQL "ALTER TABLE properties RENAME COLUMN weight TO atomic_mass;")
  echo "RENAME_PROPERTIES_WEIGHT                    : $RENAME_PROPERTIES_WEIGHT"

  # Rename melting/boiling columns to _celsius
  RENAME_PROPERTIES_MELTING_POINT=$($PSQL "ALTER TABLE properties RENAME COLUMN melting_point TO melting_point_celsius;")
  RENAME_PROPERTIES_BOILING_POINT=$($PSQL "ALTER TABLE properties RENAME COLUMN boiling_point TO boiling_point_celsius;")
  echo "RENAME_PROPERTIES_MELTING_POINT             : $RENAME_PROPERTIES_MELTING_POINT"
  echo "RENAME_PROPERTIES_BOILING_POINT             : $RENAME_PROPERTIES_BOILING_POINT"

  # Ensure NOT NULL on temperature columns
  ALTER_PROPERTIES_MELTING_POINT_NOT_NULL=$($PSQL "ALTER TABLE properties ALTER COLUMN melting_point_celsius SET NOT NULL;")
  ALTER_PROPERTIES_BOILING_POINT_NOT_NULL=$($PSQL "ALTER TABLE properties ALTER COLUMN boiling_point_celsius SET NOT NULL;")
  echo "ALTER_PROPERTIES_MELTING_POINT_NOT_NULL     : $ALTER_PROPERTIES_MELTING_POINT_NOT_NULL"
  echo "ALTER_PROPERTIES_BOILING_POINT_NOT_NULL     : $ALTER_PROPERTIES_BOILING_POINT_NOT_NULL"

  # UNIQUE / NOT NULL constraints on elements.symbol and elements.name
  ALTER_ELEMENTS_SYMBOL_UNIQUE=$($PSQL "ALTER TABLE elements ADD CONSTRAINT IF NOT EXISTS elements_symbol_unique UNIQUE(symbol);")
  ALTER_ELEMENTS_NAME_UNIQUE=$($PSQL "ALTER TABLE elements ADD CONSTRAINT IF NOT EXISTS elements_name_unique UNIQUE(name);")
  echo "ALTER_ELEMENTS_SYMBOL_UNIQUE                : $ALTER_ELEMENTS_SYMBOL_UNIQUE"
  echo "ALTER_ELEMENTS_NAME_UNIQUE                  : $ALTER_ELEMENTS_NAME_UNIQUE"

  ALTER_ELEMENTS_SYMBOL_NOT_NULL=$($PSQL "ALTER TABLE elements ALTER COLUMN symbol SET NOT NULL;")
  ALTER_ELEMENTS_NAME_NOT_NULL=$($PSQL "ALTER TABLE elements ALTER COLUMN name SET NOT NULL;")
  echo "ALTER_ELEMENTS_SYMBOL_NOT_NULL              : $ALTER_ELEMENTS_SYMBOL_NOT_NULL"
  echo "ALTER_ELEMENTS_NAME_NOT_NULL                : $ALTER_ELEMENTS_NAME_NOT_NULL"

  # Foreign key from properties.atomic_number -> elements.atomic_number
  ALTER_PROPERTIES_ATOMIC_NUMBER_FOREIGN_KEY=$($PSQL "ALTER TABLE properties ADD CONSTRAINT IF NOT EXISTS properties_atomic_number_fkey FOREIGN KEY (atomic_number) REFERENCES elements(atomic_number);")
  echo "ALTER_PROPERTIES_ATOMIC_NUMBER_FOREIGN_KEY  : $ALTER_PROPERTIES_ATOMIC_NUMBER_FOREIGN_KEY"

  # Create types table (id + varchar) and populate it
  CREATE_TBL_TYPES=$($PSQL "CREATE TABLE IF NOT EXISTS types(type_id SERIAL PRIMARY KEY, type VARCHAR(20) NOT NULL);")
  echo "CREATE_TBL_TYPES                            : $CREATE_TBL_TYPES"

  INSERT_COLUMN_TYPES_TYPE=$($PSQL "INSERT INTO types(type) SELECT DISTINCT(type) FROM properties WHERE type IS NOT NULL ON CONFLICT DO NOTHING;")
  echo "INSERT_COLUMN_TYPES_TYPE                    : $INSERT_COLUMN_TYPES_TYPE"

  # Add type_id column to properties if missing and link it
  ADD_COLUMN_PROPERTIES_TYPE_ID=$($PSQL "ALTER TABLE properties ADD COLUMN IF NOT EXISTS type_id INT;")
  ADD_FOREIGN_KEY_PROPERTIES_TYPE_ID=$($PSQL "ALTER TABLE properties ADD CONSTRAINT IF NOT EXISTS properties_type_id_fkey FOREIGN KEY(type_id) REFERENCES types(type_id);")
  echo "ADD_COLUMN_PROPERTIES_TYPE_ID               : $ADD_COLUMN_PROPERTIES_TYPE_ID"
  echo "ADD_FOREIGN_KEY_PROPERTIES_TYPE_ID          : $ADD_FOREIGN_KEY_PROPERTIES_TYPE_ID"

  UPDATE_PROPERTIES_TYPE_ID=$($PSQL "UPDATE properties SET type_id = (SELECT type_id FROM types WHERE properties.type = types.type) WHERE properties.type IS NOT NULL;")
  ALTER_COLUMN_PROPERTIES_TYPE_ID_NOT_NULL=$($PSQL "ALTER TABLE properties ALTER COLUMN type_id SET NOT NULL;")
  echo "UPDATE_PROPERTIES_TYPE_ID                   : $UPDATE_PROPERTIES_TYPE_ID"
  echo "ALTER_COLUMN_PROPERTIES_TYPE_ID_NOT_NULL    : $ALTER_COLUMN_PROPERTIES_TYPE_ID_NOT_NULL"

  # Capitalize element symbols
  UPDATE_ELEMENTS_SYMBOL=$($PSQL "UPDATE elements SET symbol = INITCAP(symbol);")
  echo "UPDATE_ELEMENTS_SYMBOL                      : $UPDATE_ELEMENTS_SYMBOL"

  # Trim trailing zeros from atomic_mass by casting to float then to text
  ALTER_VARCHAR_PROPERTIES_ATOMIC_MASS=$($PSQL "ALTER TABLE properties ALTER COLUMN atomic_mass TYPE VARCHAR(20);")
  UPDATE_FLOAT_PROPERTIES_ATOMIC_MASS=$($PSQL "UPDATE properties SET atomic_mass = CAST(CAST(atomic_mass AS FLOAT) AS TEXT);")
  echo "ALTER_VARCHAR_PROPERTIES_ATOMIC_MASS        : $ALTER_VARCHAR_PROPERTIES_ATOMIC_MASS"
  echo "UPDATE_FLOAT_PROPERTIES_ATOMIC_MASS         : $UPDATE_FLOAT_PROPERTIES_ATOMIC_MASS"

  # Insert elements 9 (Fluorine) and 10 (Neon)
  INSERT_ELEMENT_F=$($PSQL "INSERT INTO elements(atomic_number,symbol,name) VALUES(9,'F','Fluorine') ON CONFLICT DO NOTHING;")
  INSERT_PROPERTIES_F=$($PSQL "INSERT INTO properties(atomic_number,type,melting_point_celsius,boiling_point_celsius,type_id,atomic_mass) VALUES(9,'nonmetal',-220,-188.1,(SELECT type_id FROM types WHERE type='nonmetal'),'18.998') ON CONFLICT DO NOTHING;")
  echo "INSERT_ELEMENT_F                            : $INSERT_ELEMENT_F"
  echo "INSERT_PROPERTIES_F                         : $INSERT_PROPERTIES_F"

  INSERT_ELEMENT_NE=$($PSQL "INSERT INTO elements(atomic_number,symbol,name) VALUES(10,'Ne','Neon') ON CONFLICT DO NOTHING;")
  INSERT_PROPERTIES_NE=$($PSQL "INSERT INTO properties(atomic_number,type,melting_point_celsius,boiling_point_celsius,type_id,atomic_mass) VALUES(10,'nonmetal',-248.6,-246.1,(SELECT type_id FROM types WHERE type='nonmetal'),'20.18') ON CONFLICT DO NOTHING;")
  echo "INSERT_ELEMENT_NE                           : $INSERT_ELEMENT_NE"
  echo "INSERT_PROPERTIES_NE                        : $INSERT_PROPERTIES_NE"

  # Delete the sentinel row (atomic_number = 1000)
  DELETE_PROPERTIES_1000=$($PSQL "DELETE FROM properties WHERE atomic_number=1000;")
  DELETE_ELEMENTS_1000=$($PSQL "DELETE FROM elements WHERE atomic_number=1000;")
  echo "DELETE_PROPERTIES_1000                      : $DELETE_PROPERTIES_1000"
  echo "DELETE_ELEMENTS_1000                        : $DELETE_ELEMENTS_1000"

  # Drop the old 'type' column from properties
  DELETE_COLUMN_PROPERTIES_TYPE=$($PSQL "ALTER TABLE properties DROP COLUMN IF EXISTS type;")
  echo "DELETE_COLUMN_PROPERTIES_TYPE               : $DELETE_COLUMN_PROPERTIES_TYPE"
}

START_PROGRAM() {
  CHECK=$($PSQL "SELECT COUNT(*) FROM elements WHERE atomic_number=1000;")
  if [[ $CHECK -gt 0 ]]
  then
    FIX_DB
    clear
  fi
  MAIN_PROGRAM $1
}

START_PROGRAM $1
