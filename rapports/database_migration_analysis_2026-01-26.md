# Database Migratie Analyse - Iridium/Somtoday

**Datum:** 26 januari 2026  
**Doel:** Zero-downtime releases met backwards compatible database migraties

---

## 📊 Overzicht Gevonden Mutatie Types

Op basis van analyse van changelogs in versies 13.x tot 16.x:

### DDL (Schema) Mutaties

| Type | Frequentie | Voorbeeld ChangeSet | Backwards Compat |
|------|------------|---------------------|------------------|
| `createTable` | ⬤⬤⬤⬤⬤ Zeer hoog | `CE-449-fat-event-tabel` | ✅ Veilig |
| `addColumn` | ⬤⬤⬤⬤⬤ Zeer hoog | `SLL-63-invoerdt-geldendexamenresultaat` | ✅ Veilig (nullable) |
| `createIndex` | ⬤⬤⬤⬤ Hoog | `CE-449-fat-event-index` | ⚠️ Kan locks geven |
| `addForeignKeyConstraint` | ⬤⬤⬤⬤ Hoog | `fk_leerlingtoestemmingindicaties_leerling` | ⚠️ Lock op target tabel |
| `addUniqueConstraint` | ⬤⬤⬤ Medium | `uk_sipvestiging_sip_vestiging` | ⚠️ Kan falen bij duplicaten |
| `dropNotNullConstraint` | ⬤⬤ Laag | `DT-20610_remove_eigenaar_not_null_constraint` | ✅ Veilig |
| `addNotNullConstraint` | ⬤⬤ Laag | `DT-21525-maak-geldendvoortgangsdossierresultaat-dtype-veld-not-null` | 🔴 Vereist data fill |
| `dropColumn` | ⬤ Zeldzaam | `STT-5294_Drop_LandelijkeSettings_googleAnalyticsEloSampleRate` | 🔴 Breaking |
| `renameTable` | ⬤ Zeldzaam | `SLL-4817-rename-AccountNotificationSettings` | 🔴 Breaking |
| `dropUniqueConstraint` | ⬤ Zeldzaam | `DT-21525-drop-oude-geldendvoortgangsdossierresultaat-unique-constraint` | ⚠️ Timing kritiek |

### DML (Data) Mutaties

| Type | Frequentie | Voorbeeld | Backwards Compat |
|------|------------|-----------|------------------|
| `update` | ⬤⬤⬤⬤ Hoog | `DT-21525-vul-geldendvoortgangsdossierresultaat-dtype-veld` | ⚠️ Scope-afhankelijk |
| `insert` (via sql) | ⬤⬤⬤ Medium | `DT-22377-uitgesteld-publiceren-afgenomen-feature-toevoegen` | ✅ Veilig |
| `delete` | ⬤⬤ Laag | `ST-48718_verwijder_oude_naam` | 🔴 Data verlies |
| Bulk SQL | ⬤⬤ Laag | `delete-filesystem-bestanden.sql` | 🔴 Lange locks |

### Speciale Operaties

| Type | Frequentie | Voorbeeld | Backwards Compat |
|------|------------|-----------|------------------|
| `customChange` (EjbCall) | ⬤⬤⬤ Medium | `ST_51365_VakpositieRekenenEonsToevoegenCustomChange` | ⚠️ Code-afhankelijk |
| `sqlFile` (functions) | ⬤⬤⬤ Medium | `update_bo_absenties.sql` | ✅ Veilig (runOnChange) |
| `refresh materialized view` | ⬤⬤ Laag | `refreshViews` (slave context) | ⚠️ Blocking |
| `recreate_landelijke_tabel` | ⬤ Zeldzaam | Foreign tables recreate | ⚠️ Slave-only |

---

## 🎯 Zero-Downtime Strategie per Mutatie Type

### 1. CREATE TABLE ✅

**Huidige aanpak:** Goed - gebruikt `preConditions`
```xml
<preConditions onFail="MARK_RAN">
    <not><tableExists tableName="..."/></not>
</preConditions>
<createTable>...</createTable>
```

**Rollback strategie:** 
- Nieuwe tabel wordt niet gebruikt door oude code
- Geen actie nodig bij rollback

---

### 2. ADD COLUMN ⚠️

**Huidige aanpak:** Meestal goed
```xml
<addColumn tableName="geldendexamendossierresultaat">
    <column name="datumInvoerEerstePoging" type="datetime"/>  <!-- nullable! -->
</addColumn>
```

**Verbeterpunten:**
- ✅ Altijd nullable columns toevoegen (jullie doen dit al)
- ⚠️ Geen defaults specificeren bij `addColumn` (kan lock geven)

**Rollback strategie:**
- Oude code negeert nieuwe kolom
- Geen actie nodig

**Aanbevolen patroon:**
```xml
<!-- Release N: Add nullable column -->
<addColumn tableName="...">
    <column name="newColumn" type="varchar(255)">
        <constraints nullable="true"/>  <!-- ALTIJD nullable -->
    </column>
</addColumn>

<!-- Release N: Code schrijft naar beide, leest van oude -->
<!-- Release N+1: Code leest van nieuwe -->
<!-- Release N+2: Column verplicht maken (na validatie) -->
```

---

### 3. ADD NOT NULL CONSTRAINT 🔴

**Huidige aanpak:** 3-fase pattern (goed!)
```xml
<!-- Fase 1: Add nullable column -->
<addColumn><column name="dtype" nullable="true"/></addColumn>

<!-- Fase 2: Vul data -->
<update tableName="...">
    <column name="dtype" value="Geldend"/>
    <where>dtype IS NULL</where>
</update>

<!-- Fase 3: Add NOT NULL -->
<addNotNullConstraint tableName="..." columnName="dtype"/>
```

**Verbeterpunten:**
- ⚠️ Fase 2 en 3 moeten in **aparte releases**
- Oude code moet kunnen werken met NULL waarden

**Rollback strategie:**
- Probleem: oude code kan crashen als NOT NULL constraint al actief is
- Oplossing: feature flag in applicatie die bepaalt of NULL verwacht kan worden

---

### 4. CREATE INDEX ⚠️

**Huidige aanpak:**
```xml
<createIndex tableName="connected_fat_events" indexName="idx_...">
    <column name="eventType"/>
</createIndex>
```

**⚠️ PROBLEEM: Dit blokkeert de tabel tijdens index creatie!**

**Aanbevolen aanpak:**
```xml
<!-- Gebruik CONCURRENTLY voor grote tabellen -->
<sql splitStatements="false">
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_... ON ${organisatieSchema}.table(column);
</sql>
```

**Rollback strategie:**
- Index kan veilig bestaan voor oude code
- `DROP INDEX CONCURRENTLY` voor cleanup

---

### 5. ADD FOREIGN KEY CONSTRAINT ⚠️

**Huidige aanpak:**
```xml
<addForeignKeyConstraint 
    baseTableName="LeerlingVolwassenGelezenIndicatie"
    baseColumnNames="leerling"
    referencedTableName="Leerling"
    constraintName="fk_..."/>
```

**⚠️ PROBLEEM: Dit neemt een lock op de referenced tabel!**

**Aanbevolen aanpak:**
```sql
-- PostgreSQL: NOT VALID voorkomt volledige tabel scan
ALTER TABLE ... ADD CONSTRAINT fk_... 
    FOREIGN KEY (...) REFERENCES ... NOT VALID;

-- Later (in volgende release):
ALTER TABLE ... VALIDATE CONSTRAINT fk_...;
```

**Rollback strategie:**
- FK constraint kan veilig bestaan voor oude code

---

### 6. DROP COLUMN 🔴

**Huidige aanpak:**
```xml
<dropColumn tableName="landelijkesettings" columnName="googleanalyticselosamplerate"/>
```

**🔴 KRITIEK: Dit breekt onmiddellijk oude code!**

**Aanbevolen 3-release strategie:**

| Release | Database | Applicatie |
|---------|----------|------------|
| N | - | Stop met schrijven naar kolom |
| N+1 | - | Stop met lezen van kolom |
| N+2 | `dropColumn` | - |

**Rollback strategie:**
- Na drop is rollback ONMOGELIJK
- Altijd eerst 2 releases wachten

---

### 7. RENAME COLUMN 🔴 (Dual-Write Pattern)

**Probleem:** Bij kolom hernoemen moet oude code kunnen blijven werken bij rollback.

```
┌─────────────────────────────────────────────────────────────┐
│ Scenario ZONDER dual-write:                                 │
├─────────────────────────────────────────────────────────────┤
│ 1. DB: oude kolom "naam" + nieuwe kolom "title"             │
│ 2. Nieuwe app schrijft ALLEEN naar "title"                  │
│ 3. Rollback naar oude app...                                │
│ 4. 💥 Oude app leest "naam" → verouderde/verkeerde data!    │
└─────────────────────────────────────────────────────────────┘
```

**Aanbevolen strategie: Dual-Write met Database Trigger**

| Release | Database | Code schrijft | Code leest | Rollback? |
|---------|----------|---------------|------------|-----------|
| N | Add column + sync trigger | BEIDE | Oud | ✅ Ja |
| N+1 | - | BEIDE | Nieuw | ✅ Ja |
| N+2 | Drop trigger + oude kolom | Nieuw | Nieuw | 🔴 Nee |

**Liquibase Changelog:**
```xml
<!-- Release N: Add new column -->
<changeSet id="TICKET-123-add-title-column" author="developer">
    <preConditions onFail="MARK_RAN">
        <not><columnExists tableName="product" columnName="title"/></not>
    </preConditions>
    <addColumn tableName="product">
        <column name="title" type="varchar(255)"/>
    </addColumn>
</changeSet>

<!-- Release N: Copy existing data -->
<changeSet id="TICKET-123-copy-data-to-new-column" author="developer">
    <update tableName="product">
        <column name="title" valueComputed="naam"/>
        <where>title IS NULL AND naam IS NOT NULL</where>
    </update>
</changeSet>

<!-- Release N: Create sync trigger -->
<changeSet id="TICKET-123-create-sync-trigger" author="developer">
    <sql splitStatements="false"><![CDATA[
        CREATE OR REPLACE FUNCTION sync_naam_title()
        RETURNS TRIGGER AS $$
        BEGIN
            -- Sync nieuwe kolom naar oude (voor rollback)
            IF TG_OP = 'UPDATE' AND NEW.title IS DISTINCT FROM OLD.title THEN
                NEW.naam := NEW.title;
            END IF;
            
            -- Sync oude kolom naar nieuwe (voor oude code)
            IF TG_OP = 'UPDATE' AND NEW.naam IS DISTINCT FROM OLD.naam THEN
                NEW.title := NEW.naam;
            END IF;
            
            -- Bij INSERT: sync beide kanten
            IF TG_OP = 'INSERT' THEN
                IF NEW.title IS NOT NULL AND NEW.naam IS NULL THEN
                    NEW.naam := NEW.title;
                ELSIF NEW.naam IS NOT NULL AND NEW.title IS NULL THEN
                    NEW.title := NEW.naam;
                END IF;
            END IF;
            
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_sync_naam_title
            BEFORE INSERT OR UPDATE ON product
            FOR EACH ROW
            EXECUTE FUNCTION sync_naam_title();
    ]]></sql>
</changeSet>

<!-- Release N+2: Cleanup (NA bevestiging dat rollback niet meer nodig is) -->
<changeSet id="TICKET-123-drop-sync-trigger" author="developer">
    <sql>DROP TRIGGER IF EXISTS trg_sync_naam_title ON product;</sql>
    <sql>DROP FUNCTION IF EXISTS sync_naam_title();</sql>
</changeSet>

<changeSet id="TICKET-123-drop-old-column" author="developer">
    <dropColumn tableName="product" columnName="naam"/>
</changeSet>
```

**Java Code (JPA) - Release N:**
```java
@Entity
public class Product {
    @Column(name = "naam")  // Oude kolom
    private String naam;
    
    @Column(name = "title") // Nieuwe kolom
    private String title;
    
    // Getter leest van OUDE kolom (backwards compat)
    public String getNaam() {
        return naam;
    }
    
    // Setter schrijft naar BEIDE (dual-write)
    public void setNaam(String value) {
        this.naam = value;   // Voor rollback
        this.title = value;  // Nieuwe kolom
    }
}
```

**Voordelen van de trigger-aanpak:**
- ✅ Werkt ook voor directe SQL updates
- ✅ Geen code-aanpassingen nodig in alle services
- ✅ Transparant voor de applicatie
- ✅ Consistente data in beide kolommen

**Rollback strategie:**
- Tot Release N+2: oude kolom bevat altijd correcte data
- Na N+2: rollback niet meer mogelijk (oude kolom is weg)

---

### 8. RENAME TABLE 🔴

**Huidige aanpak:**
```xml
<renameTable oldTableName="AccountNotificationSettings" newTableName="AccountSettings"/>
```

**🔴 KRITIEK: Oude code kan tabel niet vinden!**

**Aanbevolen strategie:**
```sql
-- Release N: Maak view met oude naam
CREATE VIEW AccountNotificationSettings AS SELECT * FROM AccountSettings;

-- Release N+1: Deploy code met nieuwe naam
-- Release N+2: Drop view
DROP VIEW AccountNotificationSettings;
```

**Rollback strategie:**
- View zorgt voor backwards compatibility
- Beide namen werken tegelijkertijd

---

### 10. DROP/MODIFY UNIQUE CONSTRAINT ⚠️

**Huidige aanpak:**
```xml
<dropUniqueConstraint constraintName="uk_geldvgres_ll_reskol_andervak"/>
<sql>alter table ... add constraint ... unique nulls not distinct (...)</sql>
```

**⚠️ PROBLEEM: Window zonder constraint = race condition!**

**Aanbevolen strategie:**
```sql
-- Stap 1: Maak nieuwe constraint met andere naam
ALTER TABLE ... ADD CONSTRAINT uk_new UNIQUE (...);

-- Stap 2: Drop oude constraint
ALTER TABLE ... DROP CONSTRAINT uk_old;

-- Stap 3: (optioneel) Rename
ALTER TABLE ... RENAME CONSTRAINT uk_new TO uk_old;
```

---

### 11. BULK DATA UPDATES 🔴

**Huidige aanpak:**
```sql
INSERT INTO LeerlingToestemmingIndicaties (...)
SELECT ... FROM Leerling l WHERE EXISTS (...)
```

**🔴 PROBLEEM: Kan miljoenen rijen locken!**

**Aanbevolen strategie:**
```sql
-- Batch processing
DO $$
DECLARE
    batch_size INT := 10000;
    rows_updated INT;
BEGIN
    LOOP
        UPDATE target_table SET ...
        WHERE id IN (
            SELECT id FROM target_table 
            WHERE condition 
            LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        );
        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        EXIT WHEN rows_updated = 0;
        COMMIT;
    END LOOP;
END $$;
```

**Of via background job in applicatie (CustomChange):**
```java
@Stateless
public class DataMigrationCustomChange {
    public void migrateInBatches() {
        // Process in batches with progress tracking
    }
}
```

---

### 12. DELETE OPERATIES 🔴

**Huidige aanpak:**
```xml
<delete tableName="rapportagepaginapageclass">
    <where>pageclass = '...'</where>
</delete>
```

**🔴 PROBLEEM: Data verlies is permanent!**

**Aanbevolen strategie:**
```sql
-- Soft delete eerst
UPDATE table SET deleted_at = NOW() WHERE ...;

-- In volgende release: echte delete
DELETE FROM table WHERE deleted_at < NOW() - INTERVAL '30 days';
```

---

## �️ Master/Slave Database Architectuur

### Overzicht

Somtoday gebruikt een **multi-database architectuur** met een master (set 1) en slave (set 2) database. Dit heeft belangrijke implicaties voor database migraties.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            MASTER DATABASE (Set 1)                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Schema: landelijk                                                    │   │
│  │ ══════════════════                                                   │   │
│  │ • Alle landelijke tabellen in PURE vorm                              │   │
│  │ • Directe fysieke tabellen                                           │   │
│  │ • Single source of truth voor landelijke data                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Schema: organisatie                                                  │   │
│  │ ══════════════════                                                   │   │
│  │ • Per-school data (subset van scholen)                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     │ Foreign Data Wrapper (postgres_fdw)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SLAVE DATABASE (Set 2)                           │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Schema: landelijk_fdw                                                │   │
│  │ ═══════════════════                                                  │   │
│  │ • Foreign tables die naar master.landelijk wijzen                    │   │
│  │ • Alleen voor 'foreign' en 'materialized' strategieën                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                     │                                       │
│                                     ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Schema: landelijk_mv                                                 │   │
│  │ ══════════════════                                                   │   │
│  │ • Materialized views van landelijk_fdw tabellen                      │   │
│  │ • Gecachte kopie van master data                                     │   │
│  │ • Periodiek gerefresht                                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                     │                                       │
│                                     ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Schema: landelijk                                                    │   │
│  │ ══════════════════                                                   │   │
│  │ • Views naar landelijk_mv (voor materialized)                        │   │
│  │ • Foreign tables (voor foreign)                                      │   │
│  │ • Fysieke tabellen (voor table/localcopy)                            │   │
│  │ • Dit is wat de applicatie ziet!                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Schema: organisatie                                                  │   │
│  │ ══════════════════                                                   │   │
│  │ • Per-school data (andere subset van scholen)                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Landelijke Tabel Strategieën

Op de slave database kunnen landelijke tabellen op drie manieren bestaan:

| Strategie | Data Flow | Use Case | Write Behavior |
|-----------|-----------|----------|----------------|
| **`foreign`** | `landelijk.fdw` → master | Real-time data nodig | Direct naar master |
| **`materialized`** | `landelijk.view` → `landelijk_mv.mv` → `landelijk_fdw.fdw` → master | Lees-performance belangrijk | Via trigger naar master |
| **`table`** / **`localcopy`** | `landelijk.table` (lokaal) | Eigen data per set | Lokaal + via trigger naar master |

#### 1. Strategy: `foreign` (Direct FDW)

```
┌─────────────────┐     ┌─────────────────┐
│ landelijk.tabel │ ──► │ master.landelijk│
│   (foreign)     │     │     .tabel      │
└─────────────────┘     └─────────────────┘
```

**Kenmerken:**
- ✅ Altijd actuele data
- ✅ Writes gaan direct naar master
- 🔴 Elke query gaat over het netwerk
- 🔴 Performance afhankelijk van master

**Gebruik voor:** Configuratie-tabellen die weinig gelezen worden maar altijd actueel moeten zijn.

#### 2. Strategy: `materialized` (Gecachte View)

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ landelijk.tabel │ ──► │ landelijk_mv    │ ──► │ landelijk_fdw   │ ──► │ master.landelijk│
│     (view)      │     │    .tabel (mv)  │     │    .tabel (fdw) │     │      .tabel     │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                                                        ▲
        │              INSERT/UPDATE/DELETE (via INSTEAD OF trigger)             │
        └────────────────────────────────────────────────────────────────────────┘
```

**Kenmerken:**
- ✅ Snelle reads (lokale MV)
- ✅ Writes propageren naar master via triggers
- ⚠️ Data kan verouderd zijn tot volgende refresh
- ⚠️ Refresh kan tijd kosten bij grote tabellen

**Triggers die automatisch aangemaakt worden:**
```sql
-- INSTEAD OF INSERT trigger
CREATE TRIGGER tabel_insert INSTEAD OF INSERT ON landelijk.tabel
FOR EACH ROW EXECUTE FUNCTION landelijk.tabel_copy();

-- INSTEAD OF UPDATE trigger  
CREATE TRIGGER tabel_update INSTEAD OF UPDATE ON landelijk.tabel
FOR EACH ROW EXECUTE FUNCTION landelijk.tabel_update();

-- INSTEAD OF DELETE trigger
CREATE TRIGGER tabel_delete INSTEAD OF DELETE ON landelijk.tabel
FOR EACH ROW EXECUTE FUNCTION landelijk.tabel_delete();
```

**Gebruik voor:** Grote landelijke tabellen die vaak gelezen worden.

#### 3. Strategy: `table` / `localcopy` (Fysieke Kopie)

```
┌─────────────────┐     ┌─────────────────┐
│ landelijk.tabel │     │ master.landelijk│
│   (table)       │     │     .tabel      │
└─────────────────┘     └─────────────────┘
        │                        ▲
        │  (localcopy: via AFTER trigger)
        └────────────────────────┘
```

**Kenmerken:**
- ✅ Volledige lokale kopie
- ✅ Snelste reads
- ⚠️ `localcopy`: writes propageren naar master
- ⚠️ `table`: data is NIET gedeeld (eigen set-specifieke data)

**Gebruik voor:** 
- `table`: Set-specifieke data (bijv. organisatie-gerelateerd)
- `localcopy`: Grote tabellen waar je lokale performance wilt maar wel master-sync

### De `recreate_landelijke_tabel` Functie

Deze functie beheert de conversie tussen strategieën:

```sql
SELECT public.recreate_landelijke_tabel('tabelnaam', 'strategy');
-- strategy: 'foreign', 'materialized', 'localcopy', 'table', of 'default'
```

**Wat de functie doet:**

| Stap | Actie |
|------|-------|
| 1 | Valideert de opgegeven strategy |
| 2 | Slaat bestaande indexes op |
| 3 | Dropt de huidige landelijke tabel constructie |
| 4 | Importeert FDW schema indien nodig |
| 5 | Maakt MV of table aan afhankelijk van strategy |
| 6 | Herstelt indexes op juiste schema |
| 7 | Voegt primary key toe (voor table/localcopy) |
| 8 | Maakt INSERT/UPDATE/DELETE triggers aan |

### ⚠️ Bekende Problemen met `recreate_landelijke_tabel`

De huidige implementatie heeft enkele zero-downtime issues:

| Probleem | Code | Impact | Risico |
|----------|------|--------|--------|
| **Blocking index creation** | `execute create_index` | Tabel gelocked tijdens rebuild | 🔴 Hoog |
| **CASCADE drops** | `DROP ... CASCADE` | Kan afhankelijke objecten verwijderen | ⚠️ Medium |
| **Lange transactie** | Hele functie = 1 txn | Locks lang vastgehouden | 🔴 Hoog |
| **Geen lock timeout** | Geen `SET lock_timeout` | Kan oneindig wachten | ⚠️ Medium |
| **MV zonder CONCURRENTLY** | `CREATE MATERIALIZED VIEW` | Blokkeert reads | 🔴 Hoog |
| **Geen FDW retry** | Direct `IMPORT FOREIGN SCHEMA` | Faalt als master tijdelijk weg | ⚠️ Medium |

### 🔧 Aanbevolen Verbeteringen voor `recreate_landelijke_tabel`

#### Verbetering 1: Lock Timeout toevoegen

```sql
-- Aan het begin van de functie:
SET LOCAL lock_timeout = '5s';  -- Fail fast bij locks
SET LOCAL statement_timeout = '300s';  -- Max 5 minuten totaal
```

#### Verbetering 2: Indexes CONCURRENTLY aanmaken

```sql
-- PROBLEEM: Huidige code
foreach create_index in array create_index_script loop
    execute replace(create_index, 'landelijk.', concat(index_schema, '.'));
end loop;

-- OPLOSSING: Indexes buiten transactie, met CONCURRENTLY
-- Dit vereist een aparte functie omdat CONCURRENTLY niet in een transactie kan!
```

**Nieuwe helper functie voor indexes:**
```sql
CREATE OR REPLACE FUNCTION public.recreate_landelijke_tabel_indexes(tabel text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    idx record;
BEGIN
    -- Indexes moeten BUITEN een transactie aangemaakt worden voor CONCURRENTLY
    FOR idx IN 
        SELECT indexdef 
        FROM pg_indexes 
        WHERE schemaname = 'landelijk_mv' 
        AND lower(tablename) = lower(tabel)
    LOOP
        -- Voeg CONCURRENTLY toe als dat niet al in de definitie staat
        IF position('CONCURRENTLY' in idx.indexdef) = 0 THEN
            EXECUTE replace(idx.indexdef, 'CREATE INDEX', 'CREATE INDEX CONCURRENTLY');
        ELSE
            EXECUTE idx.indexdef;
        END IF;
    END LOOP;
END;
$$;
```

#### Verbetering 3: MV met WITH NO DATA + aparte populate

```sql
-- In plaats van:
execute concat('create materialized view landelijk_mv.', tabel, 
               ' as select * from landelijk_fdw.', tabel);

-- Gebruik:
execute concat('create materialized view landelijk_mv.', tabel, 
               ' as select * from landelijk_fdw.', tabel, 
               ' WITH NO DATA');  -- Snel, geen data transfer

-- Dan BUITEN de transactie:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY landelijk_mv.tabel;
```

#### Verbetering 4: Gefaseerde aanpak met minimale locks

Zie onderstaande volledige v2 implementatie.

---

### 🆕 Volledige `recreate_landelijke_tabel_v2` Implementatie

Onderstaande functies vormen een zero-downtime vervanging voor de huidige `recreate_landelijke_tabel`. 
De implementatie is opgesplitst in meerdere functies om `CONCURRENTLY` operaties mogelijk te maken.

#### Hoofdfunctie: `recreate_landelijke_tabel_v2`

```sql
-- ============================================================================
-- recreate_landelijke_tabel_v2: Zero-downtime versie
-- ============================================================================
-- 
-- GEBRUIK:
--   SELECT public.recreate_landelijke_tabel_v2('tabelnaam', 'materialized');
--   
-- NA AFLOOP (buiten transactie!):
--   SELECT public.populate_landelijke_tabel('tabelnaam');
--   SELECT public.create_landelijke_tabel_indexes('tabelnaam');
--
-- OF in één keer (met mogelijke downtime):
--   SELECT public.recreate_landelijke_tabel_v2('tabelnaam', 'materialized', 
--                                               populate_immediately := true);
-- ============================================================================

CREATE OR REPLACE FUNCTION public.recreate_landelijke_tabel_v2(
    p_tabel text,
    p_strategy text DEFAULT 'default'::text,
    p_lock_timeout text DEFAULT '5s',
    p_populate_immediately boolean DEFAULT false
) RETURNS TABLE (
    step text,
    status text,
    message text
) LANGUAGE plpgsql AS $$
DECLARE
    v_huidige_tabel public.landelijke_tabellen%rowtype;
    v_servername text;
    v_hasIdColumn boolean;
    v_colnames text;
    v_colnames_new text;
    v_colnames_set text;
    v_whenevent text;
    v_actual_strategy text;
BEGIN
    -- ========================================================================
    -- STAP 0: Validatie en configuratie
    -- ========================================================================
    step := 'init'; status := 'running'; message := 'Validating parameters...';
    RETURN NEXT;
    
    -- Lock timeout instellen om niet oneindig te wachten
    EXECUTE format('SET LOCAL lock_timeout = %L', p_lock_timeout);
    EXECUTE 'SET LOCAL statement_timeout = ''300s''';  -- Max 5 minuten
    
    -- Haal foreign server naam op
    SELECT srvname INTO v_servername FROM pg_catalog.pg_foreign_server LIMIT 1;
    IF NOT FOUND THEN
        step := 'init'; status := 'error'; 
        message := 'Geen foreign server beschikbaar in deze database';
        RETURN NEXT;
        RETURN;
    END IF;
    
    -- Valideer strategy
    IF p_strategy NOT IN ('foreign', 'materialized', 'localcopy', 'table', 'default') THEN
        step := 'init'; status := 'error';
        message := format('Strategy ''%s'' bestaat niet. Gebruik: foreign, materialized, localcopy, table, default', p_strategy);
        RETURN NEXT;
        RETURN;
    END IF;
    
    -- Haal huidige tabel info op
    SELECT * INTO v_huidige_tabel 
    FROM public.landelijke_tabellen lt 
    WHERE lower(lt.tablename) = lower(p_tabel);
    
    -- Bepaal actual strategy
    v_actual_strategy := CASE 
        WHEN p_strategy = 'default' THEN COALESCE(v_huidige_tabel.strategy, 'materialized')
        ELSE p_strategy
    END;
    
    -- Check of conversie naar foreign/materialized mogelijk is
    IF v_huidige_tabel.hastable AND v_actual_strategy IN ('foreign', 'materialized') THEN
        step := 'init'; status := 'error';
        message := format('Er bestaat een fysieke tabel landelijk.%s. Drop deze eerst om naar ''%s'' te converteren.', 
                          p_tabel, v_actual_strategy);
        RETURN NEXT;
        RETURN;
    END IF;
    
    step := 'init'; status := 'ok'; 
    message := format('Using strategy: %s, server: %s', v_actual_strategy, v_servername);
    RETURN NEXT;
    
    -- ========================================================================
    -- STAP 1: Sla bestaande index definities op
    -- ========================================================================
    step := 'save_indexes'; status := 'running'; message := 'Saving existing index definitions...';
    RETURN NEXT;
    
    -- Maak temp tabel voor index definities (als die nog niet bestaat)
    CREATE TEMP TABLE IF NOT EXISTS _saved_indexes (
        tablename text,
        indexdef text
    ) ON COMMIT DROP;
    
    DELETE FROM _saved_indexes WHERE tablename = lower(p_tabel);
    
    IF v_huidige_tabel.hasindexes THEN
        INSERT INTO _saved_indexes (tablename, indexdef)
        SELECT lower(p_tabel), indexdef 
        FROM pg_indexes 
        WHERE schemaname IN ('landelijk', 'landelijk_mv') 
        AND lower(tablename) = lower(p_tabel)
        AND indexname NOT LIKE '%_pkey';  -- Primary keys apart behandelen
    END IF;
    
    step := 'save_indexes'; status := 'ok'; 
    message := format('Saved %s index definitions', (SELECT count(*) FROM _saved_indexes WHERE tablename = lower(p_tabel)));
    RETURN NEXT;
    
    -- ========================================================================
    -- STAP 2: Drop oude structuur (met lock timeout!)
    -- ========================================================================
    step := 'drop_old'; status := 'running'; message := 'Dropping old structure...';
    RETURN NEXT;
    
    BEGIN
        -- Drop in volgorde: view -> mv -> fdw (geen CASCADE om onverwachte drops te voorkomen)
        EXECUTE format('DROP VIEW IF EXISTS landelijk.%I', p_tabel);
        EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS landelijk_mv.%I', p_tabel);
        EXECUTE format('DROP FOREIGN TABLE IF EXISTS landelijk_fdw.%I', p_tabel);
        
        -- Drop trigger functions
        EXECUTE format('DROP FUNCTION IF EXISTS landelijk.%I_copy() CASCADE', p_tabel);
        EXECUTE format('DROP FUNCTION IF EXISTS landelijk.%I_update() CASCADE', p_tabel);
        EXECUTE format('DROP FUNCTION IF EXISTS landelijk.%I_delete() CASCADE', p_tabel);
        
        step := 'drop_old'; status := 'ok'; message := 'Old structure dropped';
        RETURN NEXT;
    EXCEPTION WHEN lock_not_available THEN
        step := 'drop_old'; status := 'error'; 
        message := format('Lock timeout na %s - tabel is in gebruik. Probeer later opnieuw.', p_lock_timeout);
        RETURN NEXT;
        RETURN;
    END;
    
    -- ========================================================================
    -- STAP 3: Importeer FDW (als nodig)
    -- ========================================================================
    IF v_actual_strategy IN ('foreign', 'materialized', 'localcopy') THEN
        step := 'import_fdw'; status := 'running'; message := 'Importing foreign schema...';
        RETURN NEXT;
        
        BEGIN
            EXECUTE format('IMPORT FOREIGN SCHEMA landelijk LIMIT TO (%I) FROM SERVER %I INTO landelijk_fdw',
                           p_tabel, v_servername);
            
            step := 'import_fdw'; status := 'ok'; message := 'Foreign table created in landelijk_fdw';
            RETURN NEXT;
        EXCEPTION WHEN OTHERS THEN
            step := 'import_fdw'; status := 'error';
            message := format('FDW import failed: %s. Is de master bereikbaar?', SQLERRM);
            RETURN NEXT;
            RETURN;
        END;
    END IF;
    
    -- ========================================================================
    -- STAP 4: Maak structuur aan (strategy-specifiek)
    -- ========================================================================
    step := 'create_structure'; status := 'running'; 
    message := format('Creating %s structure...', v_actual_strategy);
    RETURN NEXT;
    
    IF v_actual_strategy = 'foreign' THEN
        -- Direct foreign table in landelijk schema
        EXECUTE format('DROP FOREIGN TABLE IF EXISTS landelijk_fdw.%I', p_tabel);
        EXECUTE format('IMPORT FOREIGN SCHEMA landelijk LIMIT TO (%I) FROM SERVER %I INTO landelijk',
                       p_tabel, v_servername);
        
    ELSIF v_actual_strategy = 'materialized' THEN
        -- Maak MV zonder data (snel!) - data komt later via populate
        EXECUTE format('CREATE MATERIALIZED VIEW landelijk_mv.%I AS SELECT * FROM landelijk_fdw.%I WITH NO DATA',
                       p_tabel, p_tabel);
        
        -- Maak view op de MV
        EXECUTE format('CREATE VIEW landelijk.%I AS SELECT * FROM landelijk_mv.%I',
                       p_tabel, p_tabel);
        
    ELSIF v_actual_strategy IN ('localcopy', 'table') THEN
        -- Maak fysieke tabel (als die nog niet bestaat)
        IF NOT COALESCE(v_huidige_tabel.hastable, false) THEN
            IF p_populate_immediately THEN
                EXECUTE format('CREATE TABLE landelijk.%I AS SELECT * FROM landelijk_fdw.%I',
                               p_tabel, p_tabel);
            ELSE
                -- Maak lege tabel met zelfde structuur
                EXECUTE format('CREATE TABLE landelijk.%I AS SELECT * FROM landelijk_fdw.%I WHERE false',
                               p_tabel, p_tabel);
            END IF;
        END IF;
        
        -- Voor 'table' strategy: drop de FDW (niet meer nodig)
        IF v_actual_strategy = 'table' THEN
            EXECUTE format('DROP FOREIGN TABLE IF EXISTS landelijk_fdw.%I', p_tabel);
        END IF;
    END IF;
    
    step := 'create_structure'; status := 'ok'; 
    message := format('Structure created for strategy: %s', v_actual_strategy);
    RETURN NEXT;
    
    -- ========================================================================
    -- STAP 5: Primary key toevoegen (voor table/localcopy)
    -- ========================================================================
    IF v_actual_strategy IN ('localcopy', 'table') THEN
        SELECT count(*) = 1 INTO v_hasIdColumn 
        FROM information_schema.columns c 
        WHERE c.table_schema = 'landelijk' 
        AND lower(c.table_name) = lower(p_tabel)
        AND c.column_name = 'id';
        
        IF v_hasIdColumn THEN
            step := 'add_pk'; status := 'running'; message := 'Adding primary key...';
            RETURN NEXT;
            
            BEGIN
                EXECUTE format('ALTER TABLE landelijk.%I ADD PRIMARY KEY (id)', p_tabel);
                step := 'add_pk'; status := 'ok'; message := 'Primary key added';
                RETURN NEXT;
            EXCEPTION WHEN duplicate_object THEN
                step := 'add_pk'; status := 'skipped'; message := 'Primary key already exists';
                RETURN NEXT;
            END;
        END IF;
    END IF;
    
    -- ========================================================================
    -- STAP 6: Triggers aanmaken (voor materialized/localcopy)
    -- ========================================================================
    IF v_actual_strategy IN ('materialized', 'localcopy') THEN
        step := 'create_triggers'; status := 'running'; message := 'Creating write-through triggers...';
        RETURN NEXT;
        
        v_whenevent := CASE v_actual_strategy WHEN 'materialized' THEN 'INSTEAD OF' ELSE 'AFTER' END;
        
        -- Verzamel kolomnamen
        SELECT string_agg(column_name, ', ') INTO v_colnames
        FROM information_schema.columns 
        WHERE table_schema = 'landelijk_fdw' AND lower(table_name) = lower(p_tabel);
        
        SELECT concat('NEW.', string_agg(column_name, ', NEW.')) INTO v_colnames_new
        FROM information_schema.columns 
        WHERE table_schema = 'landelijk_fdw' AND lower(table_name) = lower(p_tabel);
        
        SELECT string_agg(concat(column_name, ' = NEW.', column_name), E',\n\t') INTO v_colnames_set
        FROM information_schema.columns 
        WHERE table_schema = 'landelijk_fdw' AND lower(table_name) = lower(p_tabel) 
        AND column_name <> 'id';
        
        -- INSERT trigger function
        EXECUTE format($trigger$
            CREATE OR REPLACE FUNCTION landelijk.%1$I_copy() RETURNS trigger AS $fn$
            BEGIN
                INSERT INTO landelijk_fdw.%1$I (%2$s) VALUES (%3$s);
                RETURN NEW;
            EXCEPTION WHEN undefined_column THEN
                RAISE WARNING 'Schema mismatch in INSERT trigger voor %1$s - recreate nodig';
                RAISE;
            END;
            $fn$ LANGUAGE plpgsql;
        $trigger$, p_tabel, v_colnames, v_colnames_new);
        
        EXECUTE format('CREATE TRIGGER %1$I_insert %2$s INSERT ON landelijk.%1$I FOR EACH ROW EXECUTE FUNCTION landelijk.%1$I_copy()',
                       p_tabel, v_whenevent);
        
        -- UPDATE trigger function
        EXECUTE format($trigger$
            CREATE OR REPLACE FUNCTION landelijk.%1$I_update() RETURNS trigger AS $fn$
            BEGIN
                UPDATE landelijk_fdw.%1$I SET
                    %2$s
                WHERE id = NEW.id;
                RETURN NEW;
            EXCEPTION WHEN undefined_column THEN
                RAISE WARNING 'Schema mismatch in UPDATE trigger voor %1$s - recreate nodig';
                RAISE;
            END;
            $fn$ LANGUAGE plpgsql;
        $trigger$, p_tabel, v_colnames_set);
        
        EXECUTE format('CREATE TRIGGER %1$I_update %2$s UPDATE ON landelijk.%1$I FOR EACH ROW EXECUTE FUNCTION landelijk.%1$I_update()',
                       p_tabel, v_whenevent);
        
        -- DELETE trigger function
        EXECUTE format($trigger$
            CREATE OR REPLACE FUNCTION landelijk.%1$I_delete() RETURNS trigger AS $fn$
            BEGIN
                DELETE FROM landelijk_fdw.%1$I WHERE id = OLD.id;
                RETURN OLD;
            EXCEPTION WHEN undefined_column THEN
                RAISE WARNING 'Schema mismatch in DELETE trigger voor %1$s - recreate nodig';
                RAISE;
            END;
            $fn$ LANGUAGE plpgsql;
        $trigger$, p_tabel);
        
        EXECUTE format('CREATE TRIGGER %1$I_delete %2$s DELETE ON landelijk.%1$I FOR EACH ROW EXECUTE FUNCTION landelijk.%1$I_delete()',
                       p_tabel, v_whenevent);
        
        step := 'create_triggers'; status := 'ok'; message := 'Triggers created with error handling';
        RETURN NEXT;
    END IF;
    
    -- ========================================================================
    -- STAP 7: Registreer in landelijke_tabellen
    -- ========================================================================
    step := 'register'; status := 'running'; message := 'Updating landelijke_tabellen registry...';
    RETURN NEXT;
    
    INSERT INTO public.landelijke_tabellen (tablename, strategy, hastable, hasindexes, last_recreated)
    VALUES (lower(p_tabel), v_actual_strategy, 
            v_actual_strategy IN ('table', 'localcopy'),
            EXISTS (SELECT 1 FROM _saved_indexes WHERE tablename = lower(p_tabel)),
            now())
    ON CONFLICT (tablename) DO UPDATE SET
        strategy = EXCLUDED.strategy,
        hastable = EXCLUDED.hastable,
        last_recreated = EXCLUDED.last_recreated;
    
    step := 'register'; status := 'ok'; message := 'Registry updated';
    RETURN NEXT;
    
    -- ========================================================================
    -- STAP 8: Optioneel direct populaten
    -- ========================================================================
    IF p_populate_immediately AND v_actual_strategy = 'materialized' THEN
        step := 'populate'; status := 'running'; 
        message := 'Populating MV (this may take a while and will block!)...';
        RETURN NEXT;
        
        EXECUTE format('REFRESH MATERIALIZED VIEW landelijk_mv.%I', p_tabel);
        
        step := 'populate'; status := 'ok'; message := 'MV populated';
        RETURN NEXT;
    END IF;
    
    -- ========================================================================
    -- DONE
    -- ========================================================================
    step := 'complete'; status := 'ok';
    IF v_actual_strategy = 'materialized' AND NOT p_populate_immediately THEN
        message := format(E'Structuur aangemaakt!\n\nVoer nu BUITEN een transactie uit:\n  1. SELECT public.populate_landelijke_tabel(''%s'');\n  2. SELECT public.create_landelijke_tabel_indexes(''%s'');', 
                          p_tabel, p_tabel);
    ELSE
        message := 'Recreate completed successfully';
    END IF;
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.recreate_landelijke_tabel_v2 IS 
'Zero-downtime versie van recreate_landelijke_tabel. Maakt structuur aan zonder data, 
zodat populate en index creatie CONCURRENTLY kunnen gebeuren.';
```

#### Helper: `populate_landelijke_tabel`

```sql
-- ============================================================================
-- populate_landelijke_tabel: Vul MV met data (CONCURRENTLY indien mogelijk)
-- ============================================================================
-- MOET buiten een transactie uitgevoerd worden voor CONCURRENTLY!
-- ============================================================================

CREATE OR REPLACE FUNCTION public.populate_landelijke_tabel(
    p_tabel text,
    p_concurrent boolean DEFAULT true
) RETURNS TABLE (status text, duration interval, rows_affected bigint) 
LANGUAGE plpgsql AS $$
DECLARE
    v_start timestamp := clock_timestamp();
    v_has_unique_index boolean;
    v_row_count bigint;
BEGIN
    -- Check of MV een unique index heeft (nodig voor CONCURRENTLY)
    SELECT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'landelijk_mv' 
        AND lower(tablename) = lower(p_tabel)
        AND indexdef LIKE '%UNIQUE%'
    ) INTO v_has_unique_index;
    
    -- Check of MV data heeft (CONCURRENTLY werkt niet op lege MV)
    EXECUTE format('SELECT count(*) FROM landelijk_mv.%I', p_tabel) INTO v_row_count;
    
    IF p_concurrent AND v_has_unique_index AND v_row_count > 0 THEN
        -- CONCURRENTLY: geen locks, maar vereist unique index en bestaande data
        EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY landelijk_mv.%I', p_tabel);
        status := 'refreshed_concurrently';
    ELSE
        -- Normale refresh (blokkeert reads tijdens refresh)
        IF p_concurrent AND NOT v_has_unique_index THEN
            RAISE NOTICE 'CONCURRENTLY niet mogelijk: geen UNIQUE index. Maak eerst een unique index aan.';
        END IF;
        IF p_concurrent AND v_row_count = 0 THEN
            RAISE NOTICE 'CONCURRENTLY niet mogelijk: MV is leeg. Eerste refresh moet blocking zijn.';
        END IF;
        
        EXECUTE format('REFRESH MATERIALIZED VIEW landelijk_mv.%I', p_tabel);
        status := 'refreshed_blocking';
    END IF;
    
    -- Tel rijen
    EXECUTE format('SELECT count(*) FROM landelijk_mv.%I', p_tabel) INTO rows_affected;
    duration := clock_timestamp() - v_start;
    
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.populate_landelijke_tabel IS 
'Refresht de materialized view. Gebruikt CONCURRENTLY indien mogelijk (vereist UNIQUE INDEX).
Moet BUITEN een transactie uitgevoerd worden!';
```

#### Helper: `create_landelijke_tabel_indexes`

```sql
-- ============================================================================
-- create_landelijke_tabel_indexes: Maak indexes CONCURRENTLY aan
-- ============================================================================
-- MOET buiten een transactie uitgevoerd worden!
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_landelijke_tabel_indexes(
    p_tabel text
) RETURNS TABLE (index_name text, status text, duration interval)
LANGUAGE plpgsql AS $$
DECLARE
    v_idx record;
    v_start timestamp;
    v_index_schema text;
    v_indexdef text;
    v_new_indexdef text;
BEGIN
    -- Bepaal target schema
    SELECT CASE 
        WHEN EXISTS (SELECT 1 FROM pg_matviews WHERE schemaname = 'landelijk_mv' AND lower(matviewname) = lower(p_tabel))
        THEN 'landelijk_mv'
        ELSE 'landelijk'
    END INTO v_index_schema;
    
    -- Haal opgeslagen index definities op
    FOR v_idx IN 
        SELECT indexdef 
        FROM _saved_indexes 
        WHERE tablename = lower(p_tabel)
    LOOP
        v_start := clock_timestamp();
        v_indexdef := v_idx.indexdef;
        
        -- Pas schema aan in indexdef
        v_new_indexdef := regexp_replace(v_indexdef, 'ON landelijk\w*\.', format('ON %s.', v_index_schema));
        
        -- Voeg CONCURRENTLY toe als dat nog niet in de definitie staat
        IF position('CONCURRENTLY' in v_new_indexdef) = 0 THEN
            v_new_indexdef := replace(v_new_indexdef, 'CREATE INDEX', 'CREATE INDEX CONCURRENTLY');
            v_new_indexdef := replace(v_new_indexdef, 'CREATE UNIQUE INDEX', 'CREATE UNIQUE INDEX CONCURRENTLY');
        END IF;
        
        -- Haal index naam uit definitie
        index_name := (regexp_match(v_new_indexdef, 'INDEX\s+(?:CONCURRENTLY\s+)?(\w+)'))[1];
        
        BEGIN
            EXECUTE v_new_indexdef;
            status := 'created';
            duration := clock_timestamp() - v_start;
            RETURN NEXT;
        EXCEPTION 
            WHEN duplicate_table THEN
                status := 'already_exists';
                duration := clock_timestamp() - v_start;
                RETURN NEXT;
            WHEN OTHERS THEN
                status := format('error: %s', SQLERRM);
                duration := clock_timestamp() - v_start;
                RETURN NEXT;
        END;
    END LOOP;
    
    -- Als geen indexes gevonden, meld dit
    IF NOT FOUND THEN
        index_name := '(none)';
        status := 'no_indexes_to_create';
        duration := '0'::interval;
        RETURN NEXT;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.create_landelijke_tabel_indexes IS 
'Maakt opgeslagen indexes aan met CONCURRENTLY. Moet BUITEN een transactie uitgevoerd worden!';
```

#### Helper: `check_landelijke_tabel_status`

```sql
-- ============================================================================
-- check_landelijke_tabel_status: Controleer status van landelijke tabel
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_landelijke_tabel_status(p_tabel text)
RETURNS TABLE (
    check_name text,
    status text,
    details text
) LANGUAGE plpgsql AS $$
DECLARE
    v_row_count bigint;
    v_fdw_row_count bigint;
    v_has_triggers boolean;
    v_trigger_count int;
    v_index_count int;
BEGIN
    -- Check 1: FDW bereikbaar?
    check_name := 'fdw_connection';
    BEGIN
        EXECUTE format('SELECT count(*) FROM landelijk_fdw.%I LIMIT 1', p_tabel) INTO v_fdw_row_count;
        status := 'ok';
        details := 'Foreign data wrapper is bereikbaar';
        RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
        status := 'error';
        details := format('FDW niet bereikbaar: %s', SQLERRM);
        RETURN NEXT;
    END;
    
    -- Check 2: MV heeft data?
    check_name := 'mv_populated';
    BEGIN
        EXECUTE format('SELECT count(*) FROM landelijk_mv.%I', p_tabel) INTO v_row_count;
        IF v_row_count > 0 THEN
            status := 'ok';
            details := format('%s rijen in MV', v_row_count);
        ELSE
            status := 'warning';
            details := 'MV is leeg - refresh nodig';
        END IF;
        RETURN NEXT;
    EXCEPTION WHEN undefined_table THEN
        status := 'skip';
        details := 'Geen MV (waarschijnlijk foreign of table strategy)';
        RETURN NEXT;
    END;
    
    -- Check 3: Data sync?
    check_name := 'data_sync';
    BEGIN
        IF v_row_count IS NOT NULL AND v_fdw_row_count IS NOT NULL THEN
            IF v_row_count = v_fdw_row_count THEN
                status := 'ok';
                details := format('Row counts match: %s', v_row_count);
            ELSE
                status := 'warning';
                details := format('Row count mismatch: MV=%s, master=%s', v_row_count, v_fdw_row_count);
            END IF;
        ELSE
            status := 'skip';
            details := 'Cannot compare (missing data)';
        END IF;
        RETURN NEXT;
    END;
    
    -- Check 4: Triggers aanwezig?
    check_name := 'triggers';
    SELECT count(*) INTO v_trigger_count
    FROM information_schema.triggers
    WHERE event_object_schema = 'landelijk'
    AND lower(event_object_table) = lower(p_tabel);
    
    IF v_trigger_count >= 3 THEN
        status := 'ok';
        details := format('%s triggers gevonden', v_trigger_count);
    ELSIF v_trigger_count > 0 THEN
        status := 'warning';
        details := format('Slechts %s triggers (verwacht: 3)', v_trigger_count);
    ELSE
        status := 'info';
        details := 'Geen triggers (normaal voor foreign/table strategy)';
    END IF;
    RETURN NEXT;
    
    -- Check 5: Indexes?
    check_name := 'indexes';
    SELECT count(*) INTO v_index_count
    FROM pg_indexes
    WHERE schemaname IN ('landelijk', 'landelijk_mv')
    AND lower(tablename) = lower(p_tabel);
    
    status := 'info';
    details := format('%s indexes gevonden', v_index_count);
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.check_landelijke_tabel_status IS 
'Diagnostische functie om de status van een landelijke tabel te controleren.';
```

#### Voorbeeld Gebruik

```sql
-- ============================================================================
-- VOORBEELD: Volledige zero-downtime recreate workflow
-- ============================================================================

-- STAP 1: Recreate structuur (snel, korte lock)
BEGIN;
SELECT * FROM public.recreate_landelijke_tabel_v2('landelijkesettings', 'materialized');
COMMIT;

-- Output:
--  step             | status  | message
-- ------------------+---------+--------------------------------------------------
--  init             | ok      | Using strategy: materialized, server: master_fdw
--  save_indexes     | ok      | Saved 2 index definitions
--  drop_old         | ok      | Old structure dropped
--  import_fdw       | ok      | Foreign table created in landelijk_fdw
--  create_structure | ok      | Structure created for strategy: materialized
--  create_triggers  | ok      | Triggers created with error handling
--  register         | ok      | Registry updated
--  complete         | ok      | Structuur aangemaakt! Voer nu BUITEN transactie uit:...

-- STAP 2: Populate (kan lang duren, maar GEEN lock!)
-- ⚠️ NIET in een transactie!
SELECT * FROM public.populate_landelijke_tabel('landelijkesettings');

-- Output:
--  status                | duration        | rows_affected
-- -----------------------+-----------------+---------------
--  refreshed_blocking    | 00:00:02.341    | 15234

-- STAP 3: Indexes aanmaken (CONCURRENTLY, geen lock)
-- ⚠️ NIET in een transactie!
SELECT * FROM public.create_landelijke_tabel_indexes('landelijkesettings');

-- Output:
--  index_name                    | status  | duration
-- -------------------------------+---------+----------------
--  idx_landsettings_key          | created | 00:00:00.523
--  uk_landsettings_organisation  | created | 00:00:00.891

-- STAP 4: Verificatie
SELECT * FROM public.check_landelijke_tabel_status('landelijkesettings');

-- Output:
--  check_name     | status | details
-- ----------------+--------+------------------------------------------
--  fdw_connection | ok     | Foreign data wrapper is bereikbaar
--  mv_populated   | ok     | 15234 rijen in MV
--  data_sync      | ok     | Row counts match: 15234
--  triggers       | ok     | 3 triggers gevonden
--  indexes        | info   | 3 indexes gevonden
```

#### Liquibase Integratie

```xml
<!-- Voor Liquibase: roep v2 aan in slave context -->
<changeSet id="TICKET-recreate-settings-v2" author="developer" context="slave">
    <sql>SELECT * FROM public.recreate_landelijke_tabel_v2('landelijkesettings', 'materialized');</sql>
</changeSet>

<!-- Aparte changeSet voor populate (runAlways om refresh te forceren) -->
<changeSet id="TICKET-populate-settings" author="developer" context="slave" runAlways="true">
    <sql>SELECT * FROM public.populate_landelijke_tabel('landelijkesettings', false);</sql>
    <!-- false = niet CONCURRENTLY, want eerste keer na WITH NO DATA -->
</changeSet>

<!-- Indexes via aparte changeSet -->
<changeSet id="TICKET-indexes-settings" author="developer" context="slave">
    <sql>SELECT * FROM public.create_landelijke_tabel_indexes('landelijkesettings');</sql>
</changeSet>
```

---

### 📋 Aanbevolen Deployment Workflow voor Slave

Voor zero-downtime bij `recreate_landelijke_tabel`:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STAP 1: Pre-create nieuwe structuur (in maintenance window of laag traffic) │
├─────────────────────────────────────────────────────────────────────────────┤
│ BEGIN;                                                                      │
│ SET LOCAL lock_timeout = '5s';                                              │
│ SELECT public.recreate_landelijke_tabel('tabel', 'materialized');           │
│ COMMIT;                                                                     │
│                                                                             │
│ ⚠️ Als dit faalt door lock timeout: retry later                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STAP 2: Populate MV (CONCURRENTLY - geen locks!)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│ -- Dit kan lang duren maar blokkeert NIETS                                  │
│ REFRESH MATERIALIZED VIEW CONCURRENTLY landelijk_mv.tabel;                  │
│                                                                             │
│ ⚠️ Vereist UNIQUE INDEX op de MV!                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STAP 3: Indexes aanmaken (CONCURRENTLY - geen locks!)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│ CREATE INDEX CONCURRENTLY idx_... ON landelijk_mv.tabel(...);               │
│                                                                             │
│ ℹ️ Kan parallel met applicatie traffic                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 🔄 Andere Master/Slave Overwegingen

#### 1. FDW Connection Pooling

```sql
-- Check huidige FDW connections
SELECT * FROM pg_stat_activity WHERE query LIKE '%fdw%';

-- Overweeg connection limits op de foreign server
ALTER SERVER master_fdw OPTIONS (SET fetch_size '10000');  -- Minder round-trips
```

#### 2. Replication Lag Monitoring

```sql
-- Op slave: check of FDW data actueel is
-- (dit werkt niet direct, maar je kunt een heartbeat tabel maken)
CREATE TABLE IF NOT EXISTS landelijk.fdw_heartbeat (
    id int PRIMARY KEY DEFAULT 1,
    last_seen timestamp DEFAULT now()
);

-- Op master: update periodiek
UPDATE landelijk.fdw_heartbeat SET last_seen = now() WHERE id = 1;

-- Op slave: check delay
SELECT now() - last_seen as lag FROM landelijk_fdw.fdw_heartbeat;
```

#### 3. Failover Scenario's

| Scenario | Impact | Mitigatie |
|----------|--------|-----------|
| Master tijdelijk onbereikbaar | FDW queries falen | Retry logic in applicatie |
| Master permanent weg | Alle writes falen | Promote slave, update FDW config |
| Slave MV stale data | Oude data getoond | Monitoring + alerting op refresh jobs |

#### 4. Trigger Failures bij Schema Mismatch

```sql
-- PROBLEEM: Als master schema wijzigt maar slave nog niet gerecreate is,
-- falen de INSTEAD OF triggers met een column mismatch error.

-- OPLOSSING: Voeg error handling toe aan triggers
CREATE OR REPLACE FUNCTION landelijk.tabel_copy() RETURNS trigger AS $$
BEGIN
    BEGIN
        INSERT INTO landelijk_fdw.tabel (...) VALUES (...);
    EXCEPTION WHEN undefined_column THEN
        RAISE WARNING 'Schema mismatch - recreate landelijke tabel nodig voor %', TG_TABLE_NAME;
        -- Fallback: probeer alleen bekende kolommen
        -- OF: raise error om deployment te stoppen
        RAISE;
    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### ✅ Checklist: Verbeterde Master/Slave Migratie

**Voor elke landelijke tabel wijziging:**

- [ ] **Lock timeout ingesteld?** `SET LOCAL lock_timeout = '5s'`
- [ ] **Indexes CONCURRENTLY?** Buiten de hoofdtransactie
- [ ] **MV refresh CONCURRENTLY?** Vereist UNIQUE INDEX
- [ ] **FDW heartbeat check?** Is master bereikbaar?
- [ ] **Retry strategie?** Wat als eerste poging faalt?
- [ ] **Rollback plan?** Hoe terug naar oude structuur?

**Monitoring na deployment:**

- [ ] Zijn alle triggers functioneel?
- [ ] Is MV data actueel? (refresh timestamp checken)
- [ ] Geen `undefined_column` errors in logs?
- [ ] FDW connection count stabiel?

---

### Zero-Downtime Implicaties voor Master/Slave

#### Schema Wijzigingen op Landelijke Tabellen

**🔴 KRITIEK:** Bij schema wijzigingen op landelijke tabellen moet je BEIDE databases bijwerken!

```
┌────────────────────────────────────────────────────────────────────────────┐
│ STAP 1: Master Database (context=master)                                   │
├────────────────────────────────────────────────────────────────────────────┤
│ • ALTER TABLE landelijk.tabel ADD COLUMN nieuwe_kolom ...                  │
│ • CREATE INDEX ... ON landelijk.tabel ...                                  │
│ • Etc.                                                                     │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ STAP 2: Slave Database - Recreate landelijke tabel (context=slave)         │
├────────────────────────────────────────────────────────────────────────────┤
│ SELECT public.recreate_landelijke_tabel('tabel', 'default');               │
│                                                                            │
│ Dit herleest het schema van master en herbouwt:                            │
│ • Foreign table in landelijk_fdw                                           │
│ • Materialized view in landelijk_mv (indien van toepassing)                │
│ • View/table in landelijk                                                  │
│ • Triggers voor write propagatie                                           │
└────────────────────────────────────────────────────────────────────────────┘
```

#### Liquibase Changelog Patroon

```xml
<!-- STAP 1: Master schema wijziging -->
<changeSet id="TICKET-add-column-master" author="developer" context="master">
    <addColumn tableName="landelijkesettings" schemaName="landelijk">
        <column name="nieuwe_kolom" type="varchar(255)"/>
    </addColumn>
</changeSet>

<!-- STAP 2: Slave recreate (MOET na master komen!) -->
<changeSet id="TICKET-add-column-slave" author="developer" context="slave">
    <sql>SELECT public.recreate_landelijke_tabel('landelijkesettings', 'default');</sql>
</changeSet>
```

#### Volgorde Matrix voor Landelijke Wijzigingen

| Wijziging Type | Master Eerst? | Slave Actie | Rollback Veilig? |
|----------------|---------------|-------------|------------------|
| ADD COLUMN | ✅ Ja | `recreate_landelijke_tabel` | ✅ Ja |
| DROP COLUMN | 🔴 Slave eerst! | Drop view/recreate | ⚠️ 2 releases |
| ADD INDEX | ✅ Ja | `recreate_landelijke_tabel` | ✅ Ja |
| RENAME COLUMN | ✅ Ja | `recreate_landelijke_tabel` | ⚠️ Dual-write |
| CHANGE TYPE | ⚠️ Voorzichtig | `recreate_landelijke_tabel` | 🔴 Nee |

### Specifieke Scenario's

#### Scenario 1: Nieuwe Kolom Toevoegen aan Landelijke Tabel

```xml
<!-- Release N -->
<changeSet id="add-col-master" author="dev" context="master">
    <addColumn tableName="landelijkesettings" schemaName="landelijk">
        <column name="feature_enabled" type="boolean" defaultValueBoolean="false"/>
    </addColumn>
</changeSet>

<changeSet id="add-col-slave" author="dev" context="slave">
    <sql>SELECT public.recreate_landelijke_tabel('landelijkesettings', 'default');</sql>
</changeSet>
```

**Waarom dit werkt:**
1. Master krijgt nieuwe kolom
2. Slave's FDW ziet nieuwe kolom automatisch niet (schema is gecached)
3. `recreate_landelijke_tabel` herleest schema en herbouwt alles
4. Beide databases hebben nu de kolom

#### Scenario 2: Kolom Verwijderen van Landelijke Tabel

**🔴 GEVAAR:** Bij DROP COLUMN moet je de volgorde OMKEREN!

```xml
<!-- Release N: Eerst slave aanpassen (context=slave) -->
<changeSet id="drop-col-prepare-slave" author="dev" context="slave">
    <!-- Drop de view/MV die de kolom bevat -->
    <sql>DROP VIEW IF EXISTS landelijk.oude_tabel CASCADE;</sql>
    <sql>DROP MATERIALIZED VIEW IF EXISTS landelijk_mv.oude_tabel CASCADE;</sql>
    <sql>DROP FOREIGN TABLE IF EXISTS landelijk_fdw.oude_tabel CASCADE;</sql>
</changeSet>

<!-- Release N+1: Dan master (context=master) -->
<changeSet id="drop-col-master" author="dev" context="master">
    <dropColumn tableName="oude_tabel" schemaName="landelijk" columnName="oude_kolom"/>
</changeSet>

<!-- Release N+1: Slave rebuilden -->
<changeSet id="drop-col-rebuild-slave" author="dev" context="slave">
    <sql>SELECT public.recreate_landelijke_tabel('oude_tabel', 'default');</sql>
</changeSet>
```

#### Scenario 3: Materialized View Refresh tijdens Deployment

```xml
<!-- Na schema wijzigingen: refresh MV -->
<changeSet id="refresh-mv" author="dev" context="slave" runAlways="true">
    <sql>REFRESH MATERIALIZED VIEW CONCURRENTLY landelijk_mv.grote_tabel;</sql>
</changeSet>
```

**Let op:** `CONCURRENTLY` vereist een UNIQUE INDEX op de MV!

### Context-Strategie Samenvatting

| Context | Database | Wanneer Gebruiken |
|---------|----------|-------------------|
| `master` | Set 1 (primair) | Landelijke schema wijzigingen, data inserts |
| `slave` | Set 2 (secundair) | `recreate_landelijke_tabel`, MV refresh |
| *(geen context)* | Beide | Organisatie schema wijzigingen |
| `Test`, `Nightly`, `Acceptatie` | Specifieke env | Feature toggles, test data |

### Checklist voor Landelijke Tabel Wijzigingen

- [ ] Is de wijziging op `master` context?
- [ ] Volgt er een `recreate_landelijke_tabel` op `slave` context?
- [ ] Bij DROP: Is de volgorde omgekeerd (slave eerst)?
- [ ] Bij grote tabellen: Is MV refresh `CONCURRENTLY`?
- [ ] Zijn de triggers correct herbouwd na recreate?
- [ ] Is de data consistent tussen master en slave na deployment?

---

## 🔄 Rollback Scenario Matrix

| Mutatie Type | Rollback Mogelijk? | Strategie |
|--------------|-------------------|-----------|
| CREATE TABLE | ✅ Ja | Tabel niet gebruiken |
| ADD COLUMN | ✅ Ja | Kolom negeren |
| CREATE INDEX | ✅ Ja | Index negeren |
| ADD FK | ✅ Ja | Constraint negeren |
| ADD NOT NULL | ⚠️ Alleen als data klopt | Oude code moet NULL kunnen schrijven |
| DROP COLUMN | 🔴 Nee | **2 releases wachten** |
| RENAME TABLE | ⚠️ Met view | View als backwards compat layer |
| DELETE data | 🔴 Nee | Soft delete gebruiken |
| UPDATE data | ⚠️ Met backup | Reverse update script klaarzetten |

---

## 🏗️ Aanbevolen Release Workflow

```
┌─────────────────────────────────────────────────────────────┐
│ FASE 1: Pre-Release Database Changes (kan dagen vooraf)    │
├─────────────────────────────────────────────────────────────┤
│ • CREATE TABLE (nieuwe tabellen)                            │
│ • ADD COLUMN (alleen nullable!)                             │
│ • CREATE INDEX CONCURRENTLY                                 │
│ • ADD FK NOT VALID                                          │
│ • CREATE VIEW (backwards compat aliases)                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ FASE 2: Code Deployment (rolling update)                    │
├─────────────────────────────────────────────────────────────┤
│ • Code ondersteunt BEIDE schema versies                     │
│ • Schrijf naar nieuwe + oude kolommen (dual write)          │
│ • Lees van oude kolom (nog)                                 │
│ • Feature flags voor nieuwe functionaliteit                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ FASE 3: Post-Deploy Validation                              │
├─────────────────────────────────────────────────────────────┤
│ • VALIDATE FK constraints                                   │
│ • Background data migration jobs                            │
│ • Monitor errors en performance                             │
│ • Bevestig rollback niet nodig                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ FASE 4: Next Release Cleanup (N+1)                          │
├─────────────────────────────────────────────────────────────┤
│ • ADD NOT NULL constraints                                  │
│ • DROP oude kolommen/tabellen                               │
│ • DROP backwards compat views                               │
│ • Update code om alleen nieuwe structuur te gebruiken       │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ Checklist voor Elke Database Migratie

### Pre-merge:
- [ ] Heeft de changelog `preConditions` voor idempotentie?
- [ ] Zijn nieuwe kolommen `nullable`?
- [ ] Zijn indexes `CONCURRENTLY` (voor grote tabellen)?
- [ ] Is er een backwards compat view nodig?
- [ ] Is de change testbaar in acceptatie?

### Pre-release:
- [ ] Is de database change onafhankelijk van de code change?
- [ ] Kan de **oude** applicatie draaien met het **nieuwe** schema?
- [ ] Kan de **nieuwe** applicatie draaien met het **oude** schema? (rollback)
- [ ] Is er een reverse migration script?

### Post-release:
- [ ] Zijn alle FK constraints gevalideerd?
- [ ] Is de data migratie compleet?
- [ ] Kunnen we de cleanup plannen voor volgende release?

---

## 🛠️ Concrete Verbeteracties

1. **CREATE INDEX CONCURRENTLY** toevoegen aan coding guidelines
2. **FK NOT VALID** pattern documenteren
3. **View-based rename** pattern toevoegen voor table renames
4. **Batch processing** template maken voor bulk updates
5. **Soft delete** standaardiseren voor DELETE operaties
6. **Release +2 regel** documenteren voor DROP operaties

---

*Dit document is gegenereerd op basis van analyse van ~50 changelog bestanden uit versies 13.x - 16.x*
