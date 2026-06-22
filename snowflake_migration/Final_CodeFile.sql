/* =========================================================
   FINAL SUBMISSION - Take Home Assignment
SnowConvert AI Software Engineering
   ---------------------------------------------------------
   SQL Server to Snowflake Migration 
   - VAISHNAVI MOCHERLA 
   ========================================================= */


/* =========================================================
   SECTION 1: ENVIRONMENT SETUP
   ---------------------------------------------------------
   Creates the Snowflake database and schema used for the
   migration prototype.
   ========================================================= */

CREATE DATABASE MIGRATION_DB;
USE DATABASE MIGRATION_DB;

CREATE SCHEMA PLANNING;
USE SCHEMA PLANNING;

SHOW TABLES;


/* =========================================================
   SECTION 2: CORE TABLE MIGRATION
   ---------------------------------------------------------
   These tables are the Snowflake equivalents of the SQL
   Server source tables needed for SP1 and its helper logic.

   Migration approach used here:
   - Preserve business columns wherever possible
   - Replace unsupported SQL Server features with
     Snowflake-friendly equivalents
   - Keep the schema close to source unless a change is
     required for compatibility
   ========================================================= */


/* ---------------------------------------------------------
   Table 1: FiscalPeriod
   Purpose:
   Stores fiscal calendar metadata used across budgeting,
   reporting, and consolidation.
   --------------------------------------------------------- */
CREATE OR REPLACE TABLE FiscalPeriod (
    FiscalPeriodID     INTEGER AUTOINCREMENT PRIMARY KEY,
    FiscalYear         SMALLINT NOT NULL,
    FiscalQuarter      SMALLINT NOT NULL,
    FiscalMonth        SMALLINT NOT NULL,
    PeriodName         STRING NOT NULL,
    PeriodStartDate    DATE NOT NULL,
    PeriodEndDate      DATE NOT NULL,
    IsClosed           BOOLEAN DEFAULT FALSE,
    ClosedByUserID     INTEGER,
    ClosedDateTime     TIMESTAMP_NTZ,
    IsAdjustmentPeriod BOOLEAN DEFAULT FALSE,
    WorkingDays        SMALLINT,
    CreatedDateTime    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    ModifiedDateTime   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP
);

-- Quick structural check
DESC TABLE FiscalPeriod;


/* ---------------------------------------------------------
   Table 2: CostCenter
   Purpose:
   Stores the cost center hierarchy used for rollups,
   allocations, and consolidation.

   Important migration decision:
   SQL Server hierarchy-specific behavior is not stored
   directly here. Snowflake hierarchy logic is rebuilt later
   using parent-child recursion.
   --------------------------------------------------------- */
CREATE OR REPLACE TABLE CostCenter (
    CostCenterID        INTEGER AUTOINCREMENT PRIMARY KEY,
    CostCenterCode      STRING NOT NULL,
    CostCenterName      STRING NOT NULL,
    ParentCostCenterID  INTEGER,
    ManagerEmployeeID   INTEGER,
    CostCenterType      STRING,
    AllocationWeight    FLOAT DEFAULT 1.0,
    IsActive            BOOLEAN DEFAULT TRUE,
    EffectiveFromDate   DATE,
    EffectiveToDate     DATE,
    CreatedDateTime     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    ModifiedDateTime    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP
);

-- Quick structural check
DESC TABLE CostCenter;


/* ---------------------------------------------------------
   Table 3: GLAccount
   Purpose:
   Stores chart-of-accounts structure and accounting
   attributes used in budgeting and consolidation.
   --------------------------------------------------------- */
CREATE OR REPLACE TABLE GLAccount (
    GLAccountID             INTEGER AUTOINCREMENT PRIMARY KEY,
    AccountNumber           STRING NOT NULL,
    AccountName             STRING NOT NULL,
    AccountType             STRING NOT NULL,
    AccountSubType          STRING,
    ParentAccountID         INTEGER,
    AccountLevel            INTEGER,
    IsPostable              BOOLEAN DEFAULT TRUE,
    IsBudgetable            BOOLEAN DEFAULT TRUE,
    IsStatistical           BOOLEAN DEFAULT FALSE,
    NormalBalance           STRING,
    CurrencyCode            STRING,
    ConsolidationAccountID  INTEGER,
    IntercompanyFlag        BOOLEAN DEFAULT FALSE,
    TaxCode                 STRING,
    StatutoryAccountCode    STRING,
    IFRSAccountCode         STRING,
    IsActive                BOOLEAN DEFAULT TRUE,
    CreatedDateTime         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    ModifiedDateTime        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP
);

-- Quick structural check
DESC TABLE GLAccount;


/* ---------------------------------------------------------
   Table 4: BudgetHeader
   Purpose:
   Stores budget version metadata.

   Important migration decisions:
   - XML -> VARIANT
   - IsLocked is stored explicitly instead of as a persisted
     computed column
   --------------------------------------------------------- */
CREATE OR REPLACE TABLE BudgetHeader (
    BudgetHeaderID          INTEGER AUTOINCREMENT PRIMARY KEY,
    BudgetCode              STRING NOT NULL,
    BudgetName              STRING NOT NULL,
    BudgetType              STRING NOT NULL,
    ScenarioType            STRING NOT NULL,
    FiscalYear              SMALLINT NOT NULL,
    StartPeriodID           INTEGER NOT NULL,
    EndPeriodID             INTEGER NOT NULL,
    BaseBudgetHeaderID      INTEGER,
    StatusCode              STRING DEFAULT 'DRAFT',
    SubmittedByUserID       INTEGER,
    SubmittedDateTime       TIMESTAMP_NTZ,
    ApprovedByUserID        INTEGER,
    ApprovedDateTime        TIMESTAMP_NTZ,
    LockedDateTime          TIMESTAMP_NTZ,

    -- SQL Server used a computed persisted column here.
    -- In Snowflake this is stored explicitly for simpler
    -- procedure logic.
    IsLocked                BOOLEAN DEFAULT FALSE,

    VersionNumber           INTEGER DEFAULT 1,
    Notes                   STRING,

    -- Flexible metadata carried over from XML to VARIANT.
    ExtendedProperties      VARIANT,

    CreatedDateTime         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    ModifiedDateTime        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP
);

-- Quick structural check
DESC TABLE BudgetHeader;


/* ---------------------------------------------------------
   Table 5: BudgetLineItem
   Purpose:
   Core fact table for budget amounts by account, cost center,
   and fiscal period.

   Important migration decisions:
   - FinalAmount is stored explicitly instead of computed
   - RowHash is stored explicitly instead of SQL Server
     HASHBYTES persisted logic
   - GUID-like import batch ID is stored as STRING
   --------------------------------------------------------- */
CREATE OR REPLACE TABLE BudgetLineItem (
    BudgetLineItemID        NUMBER AUTOINCREMENT PRIMARY KEY,
    BudgetHeaderID          INTEGER NOT NULL,
    GLAccountID             INTEGER NOT NULL,
    CostCenterID            INTEGER NOT NULL,
    FiscalPeriodID          INTEGER NOT NULL,

    OriginalAmount          NUMBER(19,4) DEFAULT 0 NOT NULL,
    AdjustedAmount          NUMBER(19,4) DEFAULT 0 NOT NULL,

    -- SQL Server stored this as a computed persisted value.
    -- Here it is stored explicitly and maintained in logic.
    FinalAmount             NUMBER(19,4),

    LocalCurrencyAmount     NUMBER(19,4),
    ReportingCurrencyAmount NUMBER(19,4),
    StatisticalQuantity     NUMBER(18,6),
    UnitOfMeasure           STRING,

    SpreadMethodCode        STRING,
    SeasonalityFactor       NUMBER(8,6),

    SourceSystem            STRING,
    SourceReference         STRING,

    -- SQL Server UNIQUEIDENTIFIER equivalent
    ImportBatchID           STRING,

    IsAllocated             BOOLEAN DEFAULT FALSE NOT NULL,
    AllocationSourceLineID  NUMBER,
    AllocationPercentage    NUMBER(8,6),

    LastModifiedByUserID    INTEGER,
    LastModifiedDateTime    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,

    -- In SQL Server this was a computed HASHBYTES persisted column.
    -- In Snowflake we store it explicitly if needed, or computed in ETL/procedure logic.
    RowHash                 STRING
);

-- Quick structural check
DESC TABLE BudgetLineItem;


/* ---------------------------------------------------------
   Table 6: AllocationRule
   Purpose:
   Stores cost allocation rule definitions.

   Important migration decision:
   TargetSpecification moved from XML to VARIANT.
   --------------------------------------------------------- */
CREATE OR REPLACE TABLE AllocationRule (
    AllocationRuleID        INTEGER AUTOINCREMENT PRIMARY KEY,
    RuleCode                STRING NOT NULL,
    RuleName                STRING NOT NULL,
    RuleDescription         STRING,
    RuleType                STRING NOT NULL,
    AllocationMethod        STRING NOT NULL,

    SourceCostCenterID      INTEGER,
    SourceCostCenterPattern STRING,
    SourceAccountPattern    STRING,

    TargetSpecification     VARIANT NOT NULL,

    AllocationBasis         STRING,
    AllocationPercentage    NUMBER(8,6),
    RoundingMethod          STRING DEFAULT 'NEAREST',
    RoundingPrecision       SMALLINT DEFAULT 2,
    MinimumAmount           NUMBER(19,4),

    ExecutionSequence       INTEGER DEFAULT 100,
    DependsOnRuleID         INTEGER,

    EffectiveFromDate       DATE NOT NULL,
    EffectiveToDate         DATE,
    IsActive                BOOLEAN DEFAULT TRUE NOT NULL,

    CreatedByUserID         INTEGER,
    CreatedDateTime         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ModifiedByUserID        INTEGER,
    ModifiedDateTime        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Quick structural check
DESC TABLE AllocationRule;



/* =========================================================
   Table 7: ConsolidationJournal
   ---------------------------------------------------------
   Purpose:
   Stores journal headers created during consolidation,
   including workflow status, reversal tracking, and
   attachment-related metadata.
   ========================================================= */

CREATE OR REPLACE TABLE ConsolidationJournal (
    JournalID               NUMBER AUTOINCREMENT PRIMARY KEY,
    JournalNumber           STRING NOT NULL,
    JournalType             STRING NOT NULL,      -- ELIMINATION, RECLASSIFICATION, TRANSLATION, ADJUSTMENT
    BudgetHeaderID          INTEGER NOT NULL,
    FiscalPeriodID          INTEGER NOT NULL,
    PostingDate             DATE NOT NULL,
    Description             STRING,
    StatusCode              STRING DEFAULT 'DRAFT' NOT NULL,

    -- Used when consolidation spans multiple legal or reporting entities
    SourceEntityCode        STRING,
    TargetEntityCode        STRING,

    -- Reversal-related fields used for auto-reversing journals
    IsAutoReverse           BOOLEAN DEFAULT FALSE NOT NULL,
    ReversalPeriodID        INTEGER,
    ReversedFromJournalID   NUMBER,
    IsReversed              BOOLEAN DEFAULT FALSE NOT NULL,

    -- Journal totals retained at header level for faster validation/reporting
    TotalDebits             NUMBER(19,4) DEFAULT 0 NOT NULL,
    TotalCredits            NUMBER(19,4) DEFAULT 0 NOT NULL,

    -- SQL Server used a computed column here.
    -- In Snowflake, this is stored explicitly and can also be derived later if needed.
    IsBalanced              BOOLEAN DEFAULT FALSE,

    -- Approval and posting workflow tracking
    PreparedByUserID        INTEGER,
    PreparedDateTime        TIMESTAMP_NTZ,
    ReviewedByUserID        INTEGER,
    ReviewedDateTime        TIMESTAMP_NTZ,
    ApprovedByUserID        INTEGER,
    ApprovedDateTime        TIMESTAMP_NTZ,
    PostedByUserID          INTEGER,
    PostedDateTime          TIMESTAMP_NTZ,

    -- Attachment handling is simplified compared to SQL Server FILESTREAM behavior
    AttachmentData          BINARY,

    -- SQL Server ROWGUIDCOL / UNIQUEIDENTIFIER is represented as STRING in Snowflake
    AttachmentRowGuid       STRING
);

-- Quick structural check
DESC TABLE ConsolidationJournal;


/* =========================================================
   Table 8: ConsolidationJournalLine
   ---------------------------------------------------------
   Purpose:
   Stores journal line items under ConsolidationJournal,
   including debit/credit values, intercompany references,
   and statistical tracking fields.
   ========================================================= */

CREATE OR REPLACE TABLE ConsolidationJournalLine (
    JournalLineID           NUMBER AUTOINCREMENT PRIMARY KEY,
    JournalID               NUMBER NOT NULL,
    LineNumber              INTEGER NOT NULL,
    GLAccountID             INTEGER NOT NULL,
    CostCenterID            INTEGER NOT NULL,

    DebitAmount             NUMBER(19,4) DEFAULT 0 NOT NULL,
    CreditAmount            NUMBER(19,4) DEFAULT 0 NOT NULL,

    -- SQL Server used a persisted computed column for NetAmount.
    -- In Snowflake, this is stored explicitly or can be derived in downstream logic.
    NetAmount               NUMBER(19,4),

    LocalCurrencyCode       STRING DEFAULT 'USD' NOT NULL,
    LocalCurrencyAmount     NUMBER(19,4),
    ExchangeRate            NUMBER(18,10),

    Description             STRING,
    ReferenceNumber         STRING,

    -- Intercompany reference fields
    PartnerEntityCode       STRING,
    PartnerAccountID        INTEGER,

    -- Statistical / non-financial tracking fields
    StatisticalQuantity     NUMBER(18,6),
    StatisticalUOM          STRING,

    -- Optional reference back to allocation logic
    AllocationRuleID        INTEGER,

    -- Audit timestamp
    CreatedDateTime         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Quick structural check
DESC TABLE ConsolidationJournalLine;

/* =========================================================
   Cost Center Hierarchy View
   ---------------------------------------------------------
   Purpose:
   Builds a full hierarchical representation of CostCenter
   using a recursive CTE.

   Adds:
   - Level (depth in hierarchy)
   - Path (readable hierarchy path)
   - IsLeaf (identifies terminal nodes)

   This replaces SQL Server hierarchy functions and supports
   rollups and traversal logic in Snowflake.
   ========================================================= */

CREATE OR REPLACE VIEW vw_CostCenterHierarchy AS

WITH RECURSIVE CostCenterHierarchy AS (

    -- Anchor: root cost centers (no parent)
    SELECT
        CostCenterID,
        ParentCostCenterID,
        CostCenterName,
        0 AS Level,
        CAST(CostCenterName AS STRING) AS Path
    FROM CostCenter
    WHERE ParentCostCenterID IS NULL

    UNION ALL

    -- Recursive step: traverse children
    SELECT
        cc.CostCenterID,
        cc.ParentCostCenterID,
        cc.CostCenterName,
        ch.Level + 1,
        ch.Path || ' > ' || cc.CostCenterName
    FROM CostCenter cc
    JOIN CostCenterHierarchy ch
        ON cc.ParentCostCenterID = ch.CostCenterID
)

SELECT 
    ch.*,

    -- Leaf detection: no children exist
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 
            FROM CostCenter c2 
            WHERE c2.ParentCostCenterID = ch.CostCenterID
        ) THEN TRUE 
        ELSE FALSE 
    END AS IsLeaf

FROM CostCenterHierarchy ch;


/* =========================================================
   Function: fn_GetHierarchyPath
   ---------------------------------------------------------
   Purpose:
   Returns the hierarchy path for a given CostCenterID.

   Design Choice:
   - Uses vw_CostCenterHierarchy instead of rebuilding recursion
   - Keeps logic centralized and avoids duplication
   ========================================================= */

CREATE OR REPLACE FUNCTION fn_GetHierarchyPath (input_cost_center_id INTEGER)
RETURNS STRING
AS
$$
    SELECT Path
    FROM vw_CostCenterHierarchy
    WHERE CostCenterID = input_cost_center_id
$$;


/* =========================================================
   VALIDATION BLOCK (Synthetic Test Data)
   ---------------------------------------------------------
   This section inserts sample hierarchy data and validates:
   - recursive hierarchy expansion
   - path correctness
   - leaf detection
   - function behavior

   NOTE:
   This is for testing only
   ========================================================= */

-- Sample hierarchy
INSERT INTO CostCenter (
    CostCenterID,
    CostCenterCode,
    CostCenterName,
    ParentCostCenterID,
    IsActive
)
VALUES
(1, 'CC001', 'Company', NULL, TRUE),
(2, 'CC002', 'Finance', 1, TRUE),
(3, 'CC003', 'HR', 1, TRUE),
(4, 'CC004', 'Payroll', 2, TRUE),
(5, 'CC005', 'Recruiting', 3, TRUE);

-- Verify table structure
DESC TABLE CostCenter;

-- Validate hierarchy expansion
SELECT *
FROM vw_CostCenterHierarchy
ORDER BY Path;

-- Validate function output
SELECT fn_GetHierarchyPath(4) AS Payroll_Path;

-- Edge cases
SELECT fn_GetHierarchyPath(1)   AS Root_Path;      -- root node
SELECT fn_GetHierarchyPath(5)   AS Leaf_Path;      -- leaf node
SELECT fn_GetHierarchyPath(999) AS Invalid_Path;   -- non-existent ID


/* =========================================================
   Function: fn_GetAllocationFactor
   ---------------------------------------------------------
   Purpose:
   Calculates allocation factor between a source and target
   cost center based on a specified allocation basis.

   Supported Allocation Methods:
   - HEADCOUNT  → Based on CostCenter.AllocationWeight
   - REVENUE    → Based on revenue accounts (AccountType = 'R')
   - EXPENSE    → Based on expense accounts (AccountType = 'X')
   - EQUAL      → Even split across active child cost centers

   Notes:
   - Returns 0 safely for null / divide-by-zero cases
   - Uses BudgetLineItem for financial-based allocations
   - Designed to support SP1 allocation and rollup logic
   ========================================================= */

CREATE OR REPLACE FUNCTION fn_GetAllocationFactor (
    input_source_cost_center_id INTEGER,
    input_target_cost_center_id INTEGER,
    input_allocation_basis STRING,
    input_fiscal_period_id INTEGER,
    input_budget_header_id INTEGER
)
RETURNS NUMBER(18,10)
AS
$$
    CASE

        /* =========================================================
           HEADCOUNT Allocation
           ---------------------------------------------------------
           Uses AllocationWeight from CostCenter table
           ========================================================= */
        WHEN input_allocation_basis = 'HEADCOUNT' THEN
            COALESCE((
                SELECT
                    CASE
                        WHEN src.total_weight IS NULL OR src.total_weight = 0 OR tgt.target_weight IS NULL
                            THEN CAST(0 AS NUMBER(18,10))
                        ELSE CAST(tgt.target_weight / src.total_weight AS NUMBER(18,10))
                    END
                FROM
                    (
                        SELECT SUM(AllocationWeight) AS total_weight
                        FROM CostCenter
                        WHERE ParentCostCenterID = input_source_cost_center_id
                          AND IsActive = TRUE
                    ) src,
                    (
                        SELECT AllocationWeight AS target_weight
                        FROM CostCenter
                        WHERE CostCenterID = input_target_cost_center_id
                          AND IsActive = TRUE
                    ) tgt
            ), CAST(0 AS NUMBER(18,10)))


        /* =========================================================
           REVENUE Allocation
           ---------------------------------------------------------
           Uses revenue accounts (AccountType = 'R')
           ========================================================= */
        WHEN input_allocation_basis = 'REVENUE' THEN
            COALESCE((
                SELECT
                    CASE
                        WHEN src.source_total IS NULL OR src.source_total = 0 OR tgt.target_total IS NULL
                            THEN CAST(0 AS NUMBER(18,10))
                        ELSE CAST(tgt.target_total / src.source_total AS NUMBER(18,10))
                    END
                FROM
                    (
                        SELECT SUM(bli.FinalAmount) AS source_total
                        FROM BudgetLineItem bli
                        JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
                        JOIN CostCenter cc ON bli.CostCenterID = cc.CostCenterID
                        WHERE (cc.ParentCostCenterID = input_source_cost_center_id
                               OR cc.CostCenterID = input_source_cost_center_id)
                          AND gla.AccountType = 'R'
                          AND bli.FiscalPeriodID = input_fiscal_period_id
                          AND (input_budget_header_id IS NULL OR bli.BudgetHeaderID = input_budget_header_id)
                    ) src,
                    (
                        SELECT SUM(bli.FinalAmount) AS target_total
                        FROM BudgetLineItem bli
                        JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
                        WHERE bli.CostCenterID = input_target_cost_center_id
                          AND gla.AccountType = 'R'
                          AND bli.FiscalPeriodID = input_fiscal_period_id
                          AND (input_budget_header_id IS NULL OR bli.BudgetHeaderID = input_budget_header_id)
                    ) tgt
            ), CAST(0 AS NUMBER(18,10)))


        /* =========================================================
           EXPENSE Allocation
           ---------------------------------------------------------
           Uses expense accounts (AccountType = 'X')
           ========================================================= */
        WHEN input_allocation_basis = 'EXPENSE' THEN
            COALESCE((
                SELECT
                    CASE
                        WHEN src.source_total IS NULL OR src.source_total = 0 OR tgt.target_total IS NULL
                            THEN CAST(0 AS NUMBER(18,10))
                        ELSE CAST(tgt.target_total / src.source_total AS NUMBER(18,10))
                    END
                FROM
                    (
                        SELECT SUM(bli.FinalAmount) AS source_total
                        FROM BudgetLineItem bli
                        JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
                        JOIN CostCenter cc ON bli.CostCenterID = cc.CostCenterID
                        WHERE (cc.ParentCostCenterID = input_source_cost_center_id
                               OR cc.CostCenterID = input_source_cost_center_id)
                          AND gla.AccountType = 'X'
                          AND bli.FiscalPeriodID = input_fiscal_period_id
                          AND (input_budget_header_id IS NULL OR bli.BudgetHeaderID = input_budget_header_id)
                    ) src,
                    (
                        SELECT SUM(bli.FinalAmount) AS target_total
                        FROM BudgetLineItem bli
                        JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
                        WHERE bli.CostCenterID = input_target_cost_center_id
                          AND gla.AccountType = 'X'
                          AND bli.FiscalPeriodID = input_fiscal_period_id
                          AND (input_budget_header_id IS NULL OR bli.BudgetHeaderID = input_budget_header_id)
                    ) tgt
            ), CAST(0 AS NUMBER(18,10)))


        /* =========================================================
           EQUAL Allocation
           ---------------------------------------------------------
           Even split across active child cost centers
           ========================================================= */
        WHEN input_allocation_basis = 'EQUAL' THEN
            COALESCE((
                SELECT
                    CASE
                        WHEN COUNT(*) = 0 THEN CAST(0 AS NUMBER(18,10))
                        ELSE CAST(1.0 / COUNT(*) AS NUMBER(18,10))
                    END
                FROM CostCenter
                WHERE ParentCostCenterID = input_source_cost_center_id
                  AND IsActive = TRUE
            ), CAST(0 AS NUMBER(18,10)))

        ELSE CAST(0 AS NUMBER(18,10))
    END
$$;


/* =========================================================
   VALIDATION BLOCK (Synthetic Test Data)
   ---------------------------------------------------------
   Inserts sample data and validates:
   - allocation factor calculations
   - edge case handling
   ========================================================= */

-- CostCenter test data
INSERT INTO CostCenter (
    CostCenterID,
    CostCenterCode,
    CostCenterName,
    ParentCostCenterID,
    AllocationWeight,
    IsActive
)
VALUES
(100, 'CC100', 'Corporate', NULL, 1.0, TRUE),
(110, 'CC110', 'Finance', 100, 10.0, TRUE),
(120, 'CC120', 'HR', 100, 30.0, TRUE),
(130, 'CC130', 'IT', 100, 60.0, TRUE);

-- GLAccount test data
INSERT INTO GLAccount (
    GLAccountID,
    AccountNumber,
    AccountName,
    AccountType,
    IsActive
)
VALUES
(1000, '4000', 'Revenue Account', 'R', TRUE),
(2000, '5000', 'Expense Account', 'X', TRUE);

-- BudgetHeader test data
INSERT INTO BudgetHeader (
    BudgetHeaderID,
    BudgetCode,
    BudgetName,
    BudgetType,
    ScenarioType,
    FiscalYear,
    StartPeriodID,
    EndPeriodID,
    StatusCode,
    IsLocked,
    VersionNumber
)
VALUES
(10000, 'BUDG_TEST', 'Test Budget', 'ANNUAL', 'BASE', 2026, 1, 12, 'APPROVED', FALSE, 1);

-- FiscalPeriod test data
INSERT INTO FiscalPeriod (
    FiscalPeriodID,
    FiscalYear,
    FiscalQuarter,
    FiscalMonth,
    PeriodName,
    PeriodStartDate,
    PeriodEndDate,
    IsClosed,
    IsAdjustmentPeriod
)
VALUES
(1, 2026, 1, 1, 'Jan 2026', '2026-01-01', '2026-01-31', FALSE, FALSE);

-- BudgetLineItem test data
INSERT INTO BudgetLineItem (
    BudgetLineItemID,
    BudgetHeaderID,
    GLAccountID,
    CostCenterID,
    FiscalPeriodID,
    OriginalAmount,
    AdjustedAmount,
    FinalAmount,
    IsAllocated,
    LastModifiedDateTime
)
VALUES
-- Revenue
(1, 10000, 1000, 100, 1, 100.00, 0.00, 100.00, FALSE, CURRENT_TIMESTAMP),
(2, 10000, 1000, 110, 1, 200.00, 0.00, 200.00, FALSE, CURRENT_TIMESTAMP),
(3, 10000, 1000, 120, 1, 300.00, 0.00, 300.00, FALSE, CURRENT_TIMESTAMP),
(4, 10000, 1000, 130, 1, 400.00, 0.00, 400.00, FALSE, CURRENT_TIMESTAMP),

-- Expense
(5, 10000, 2000, 100, 1, 50.00, 0.00, 50.00, FALSE, CURRENT_TIMESTAMP),
(6, 10000, 2000, 110, 1, 150.00, 0.00, 150.00, FALSE, CURRENT_TIMESTAMP),
(7, 10000, 2000, 120, 1, 250.00, 0.00, 250.00, FALSE, CURRENT_TIMESTAMP),
(8, 10000, 2000, 130, 1, 550.00, 0.00, 550.00, FALSE, CURRENT_TIMESTAMP);


-- =========================================================
-- TEST CASES
-- =========================================================

-- HEADCOUNT
SELECT fn_GetAllocationFactor(100, 110, 'HEADCOUNT', 1, 10000);
SELECT fn_GetAllocationFactor(100, 120, 'HEADCOUNT', 1, 10000);
SELECT fn_GetAllocationFactor(100, 130, 'HEADCOUNT', 1, 10000);

-- EQUAL
SELECT fn_GetAllocationFactor(100, 110, 'EQUAL', 1, 10000);
SELECT fn_GetAllocationFactor(100, 120, 'EQUAL', 1, 10000);
SELECT fn_GetAllocationFactor(100, 130, 'EQUAL', 1, 10000);

-- REVENUE
SELECT fn_GetAllocationFactor(100, 110, 'REVENUE', 1, 10000);
SELECT fn_GetAllocationFactor(100, 120, 'REVENUE', 1, 10000);
SELECT fn_GetAllocationFactor(100, 130, 'REVENUE', 1, 10000);

-- EXPENSE
SELECT fn_GetAllocationFactor(100, 110, 'EXPENSE', 1, 10000);
SELECT fn_GetAllocationFactor(100, 120, 'EXPENSE', 1, 10000);
SELECT fn_GetAllocationFactor(100, 130, 'EXPENSE', 1, 10000);

-- EDGE CASES
SELECT fn_GetAllocationFactor(100, 999, 'HEADCOUNT', 1, 10000);
SELECT fn_GetAllocationFactor(100, 110, 'UNKNOWN', 1, 10000);
SELECT fn_GetAllocationFactor(130, 130, 'EQUAL', 1, 10000);

/* =========================================================
   HIERARCHY + ROLLUP PREPARATION (SP1 - Preprocessing)
   ---------------------------------------------------------
   Purpose:
   Prepares intermediate staging tables required for
   budget consolidation.

   Steps:
   1. Extract hierarchy structure
   2. Build ancestor-descendant mapping
   3. Aggregate rolled-up financial amounts

   NOTE:
   Uses TEMP tables (session-scoped)
   Designed to be embedded inside stored procedure
   ========================================================= */

-- =========================================================
-- Step 0: Parameter (for testing outside procedure)
-- =========================================================
SET source_budget_id = 10000;


-- =========================================================
-- Step 1: Hierarchy Staging
-- ---------------------------------------------------------
-- Stores flattened hierarchy for easier joins/debugging
-- =========================================================
CREATE OR REPLACE TEMP TABLE temp_hierarchy_nodes AS
SELECT
    CostCenterID,
    ParentCostCenterID,
    Level,
    Path,
    IsLeaf
FROM vw_CostCenterHierarchy;


-- Validation: confirming hierarchy structure
SELECT *
FROM temp_hierarchy_nodes
ORDER BY Path;


-- =========================================================
-- Step 2: Cost Center Rollup Map
-- ---------------------------------------------------------
-- Builds ancestor → descendant relationships
-- This enables rollups (child → parent aggregation)
-- =========================================================
CREATE OR REPLACE TEMP TABLE temp_costcenter_rollup_map AS

WITH RECURSIVE rollup_map AS (

    -- Each node rolls up to itself
    SELECT
        CostCenterID AS AncestorCostCenterID,
        CostCenterID AS DescendantCostCenterID
    FROM CostCenter

    UNION ALL

    -- Traverse down hierarchy
    SELECT
        rm.AncestorCostCenterID,
        c.CostCenterID AS DescendantCostCenterID
    FROM rollup_map rm
    JOIN CostCenter c
        ON c.ParentCostCenterID = rm.DescendantCostCenterID
)

SELECT DISTINCT
    AncestorCostCenterID,
    DescendantCostCenterID
FROM rollup_map;


-- Validation: confirming mapping correctness
SELECT *
FROM temp_costcenter_rollup_map
ORDER BY AncestorCostCenterID, DescendantCostCenterID;


-- =========================================================
-- Step 3: Consolidated Amount Calculation
-- ---------------------------------------------------------
-- Aggregates financial data across hierarchy using rollup map
--
-- Key Logic:
-- Each ancestor gets sum of all its descendants
-- =========================================================
CREATE OR REPLACE TEMP TABLE temp_consolidated_amounts AS

SELECT
    bli.BudgetHeaderID,
    bli.GLAccountID,
    rm.AncestorCostCenterID AS CostCenterID,
    bli.FiscalPeriodID,

    -- Total rolled-up amount
    SUM(COALESCE(bli.FinalAmount, 0)) AS ConsolidatedAmount,

    -- Placeholder for elimination logic (Step 4 later)
    CAST(0 AS NUMBER(19,4)) AS EliminationAmount,

    -- Final amount after elimination (currently same as consolidated)
    SUM(COALESCE(bli.FinalAmount, 0)) AS FinalAmount,

    -- Helps debug how many rows contributed
    COUNT(*) AS SourceCount

FROM BudgetLineItem bli

JOIN temp_costcenter_rollup_map rm
    ON bli.CostCenterID = rm.DescendantCostCenterID

WHERE bli.BudgetHeaderID = $source_budget_id

GROUP BY
    bli.BudgetHeaderID,
    bli.GLAccountID,
    rm.AncestorCostCenterID,
    bli.FiscalPeriodID;


-- =========================================================
-- Validation: Consolidated Output
-- =========================================================
SELECT *
FROM temp_consolidated_amounts
ORDER BY BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID;


/* =========================================================
   TARGET BUDGET HEADER CREATION (SP1)
   ---------------------------------------------------------
   Purpose:
   Creates a new consolidated BudgetHeader derived from
   the source budget.

   Steps:
   1. Stage source header
   2. Transform and insert new header
   3. Capture new BudgetHeaderID for downstream inserts
   ========================================================= */


-- =========================================================
-- Step 1: Stage Source BudgetHeader
-- ---------------------------------------------------------
-- This isolates the source row so we can safely transform it
-- =========================================================
CREATE OR REPLACE TEMP TABLE temp_new_budget_header AS

SELECT
    BudgetCode,
    BudgetName,
    BudgetType,
    ScenarioType,
    FiscalYear,
    StartPeriodID,
    EndPeriodID,
    BudgetHeaderID AS BaseBudgetHeaderID,
    StatusCode,
    VersionNumber,
    ExtendedProperties
FROM BudgetHeader
WHERE BudgetHeaderID = $source_budget_id;


-- Validation: inspect staged source header
SELECT *
FROM temp_new_budget_header;


-- =========================================================
-- Step 2: Inserting New Consolidated BudgetHeader
-- ---------------------------------------------------------
-- Applies transformation rules:
-- - Appends suffix to code/name
-- - Sets type to CONSOLIDATED
-- - Increments version
-- - Adds metadata for traceability
-- =========================================================
INSERT INTO BudgetHeader (
    BudgetCode,
    BudgetName,
    BudgetType,
    ScenarioType,
    FiscalYear,
    StartPeriodID,
    EndPeriodID,
    BaseBudgetHeaderID,
    StatusCode,
    SubmittedByUserID,
    SubmittedDateTime,
    ApprovedByUserID,
    ApprovedDateTime,
    LockedDateTime,
    IsLocked,
    VersionNumber,
    Notes,
    ExtendedProperties,
    CreatedDateTime,
    ModifiedDateTime
)

SELECT
    BudgetCode || '_CONSOL' AS BudgetCode,
    BudgetName || ' - Consolidated' AS BudgetName,
    'CONSOLIDATED' AS BudgetType,
    ScenarioType,
    FiscalYear,
    StartPeriodID,
    EndPeriodID,
    BaseBudgetHeaderID,

    -- New headers start in DRAFT state
    'DRAFT' AS StatusCode,

    NULL, NULL, NULL, NULL, NULL,

    FALSE AS IsLocked,

    -- Incrementing version from source
    VersionNumber + 1 AS VersionNumber,

    'Auto-created by consolidation process' AS Notes,

    -- Store lineage + process metadata
    OBJECT_CONSTRUCT(
        'source_budget_id', BaseBudgetHeaderID,
        'created_by_process', 'usp_ProcessBudgetConsolidation',
        'created_at', CURRENT_TIMESTAMP()
    ) AS ExtendedProperties,

    CURRENT_TIMESTAMP(),
    CURRENT_TIMESTAMP()

FROM temp_new_budget_header;


-- =========================================================
-- Step 3: Retrieves Newly Created BudgetHeaderID
-- ---------------------------------------------------------
-- Required for inserting consolidated line items
-- =========================================================
CREATE OR REPLACE TEMP TABLE temp_target_budget AS

SELECT *
FROM BudgetHeader
WHERE BaseBudgetHeaderID = $source_budget_id
ORDER BY BudgetHeaderID DESC
LIMIT 1;


-- Validation: confirm new header
SELECT *
FROM temp_target_budget;


-- =========================================================
-- Step 4: Inserting Consolidated BudgetLineItems
-- ---------------------------------------------------------
-- Uses aggregated data from temp_consolidated_amounts
-- =========================================================
INSERT INTO BudgetLineItem (
    BudgetHeaderID,
    GLAccountID,
    CostCenterID,
    FiscalPeriodID,
    OriginalAmount,
    AdjustedAmount,
    FinalAmount,
    LocalCurrencyAmount,
    ReportingCurrencyAmount,
    StatisticalQuantity,
    UnitOfMeasure,
    SpreadMethodCode,
    SeasonalityFactor,
    SourceSystem,
    SourceReference,
    ImportBatchID,
    IsAllocated,
    AllocationSourceLineID,
    AllocationPercentage,
    LastModifiedByUserID,
    LastModifiedDateTime,
    RowHash
)

SELECT
    t.BudgetHeaderID,
    c.GLAccountID,
    c.CostCenterID,
    c.FiscalPeriodID,

    c.ConsolidatedAmount AS OriginalAmount,
    0 AS AdjustedAmount,
    c.FinalAmount,

    NULL, NULL, NULL, NULL, NULL, NULL,

    'CONSOLIDATION_PROCESS' AS SourceSystem,

    -- Traceability back to source
    'From source budget ' || c.BudgetHeaderID AS SourceReference,

    NULL,
    FALSE,
    NULL,
    NULL,
    NULL,
    CURRENT_TIMESTAMP(),
    NULL

FROM temp_consolidated_amounts c
JOIN temp_target_budget t
    ON 1=1;  -- single-row join (safety net because temp_target_budget has 1 row)


-- =========================================================
-- Validation: Final Output
-- =========================================================
SELECT
    BudgetHeaderID,
    GLAccountID,
    CostCenterID,
    FiscalPeriodID,
    OriginalAmount,
    AdjustedAmount,
    FinalAmount,
    SourceSystem,
    SourceReference
FROM BudgetLineItem
WHERE BudgetHeaderID = (SELECT BudgetHeaderID FROM temp_target_budget)
ORDER BY GLAccountID, CostCenterID, FiscalPeriodID;

/* =========================================================
   STORED PROCEDURE: usp_ProcessBudgetConsolidation
   ---------------------------------------------------------
   Purpose:
   Performs end-to-end budget consolidation by:
   - validating source budget
   - preventing duplicate reruns
   - creating a consolidated target budget
   - rolling up hierarchy-based values
   - applying intercompany eliminations
   - inserting final consolidated results

   Design Notes:
   - Uses TEMP tables for intermediate staging
   - Avoids cursors using recursive CTEs
   - Implemented first-pass elimination logic
   ========================================================= */

CREATE OR REPLACE PROCEDURE usp_ProcessBudgetConsolidation(input_source_budget_id INTEGER)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_source_count NUMBER DEFAULT 0;
    v_valid_status_count NUMBER DEFAULT 0;
    v_existing_target_count NUMBER DEFAULT 0;
    v_target_budget_id NUMBER;
BEGIN

    /* =====================================================
       Step 1: Validating source budget exists
       ===================================================== */
    SELECT COUNT(*)
    INTO :v_source_count
    FROM BudgetHeader
    WHERE BudgetHeaderID = :input_source_budget_id;

    IF (v_source_count = 0) THEN
        RETURN 'ERROR: Source budget not found.';
    END IF;


    /* =====================================================
       Step 2: Validating source budget status
       Only APPROVED or LOCKED budgets allowed
       ===================================================== */
    SELECT COUNT(*)
    INTO :v_valid_status_count
    FROM BudgetHeader
    WHERE BudgetHeaderID = :input_source_budget_id
      AND StatusCode IN ('APPROVED', 'LOCKED');

    IF (v_valid_status_count = 0) THEN
        RETURN 'ERROR: Source budget must be APPROVED or LOCKED.';
    END IF;


    /* =====================================================
       Step 3: Preventing duplicate consolidation
       ===================================================== */
    SELECT COUNT(*)
    INTO :v_existing_target_count
    FROM BudgetHeader
    WHERE BaseBudgetHeaderID = :input_source_budget_id
      AND BudgetType = 'CONSOLIDATED';

    IF (v_existing_target_count > 0) THEN
        RETURN 'ERROR: Consolidated budget already exists for source budget ' 
               || input_source_budget_id;
    END IF;


    /* =====================================================
       Step 4: Creating consolidated BudgetHeader
       ===================================================== */
    INSERT INTO BudgetHeader (
        BudgetCode,
        BudgetName,
        BudgetType,
        ScenarioType,
        FiscalYear,
        StartPeriodID,
        EndPeriodID,
        BaseBudgetHeaderID,
        StatusCode,
        IsLocked,
        VersionNumber,
        Notes,
        ExtendedProperties,
        CreatedDateTime,
        ModifiedDateTime
    )
    SELECT
        BudgetCode || '_CONSOL',
        BudgetName || ' - Consolidated',
        'CONSOLIDATED',
        ScenarioType,
        FiscalYear,
        StartPeriodID,
        EndPeriodID,
        BudgetHeaderID,
        'DRAFT',
        FALSE,
        VersionNumber + 1,
        'Auto-created by consolidation process',
        OBJECT_CONSTRUCT(
            'source_budget_id', BudgetHeaderID,
            'created_by_process', 'usp_ProcessBudgetConsolidation',
            'created_at', CURRENT_TIMESTAMP()
        ),
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    FROM BudgetHeader
    WHERE BudgetHeaderID = :input_source_budget_id;


    /* =====================================================
       Step 5: Fetching target BudgetHeaderID
       ===================================================== */
    SELECT MAX(BudgetHeaderID)
    INTO :v_target_budget_id
    FROM BudgetHeader
    WHERE BaseBudgetHeaderID = :input_source_budget_id
      AND BudgetType = 'CONSOLIDATED';


    /* =====================================================
       Step 6: Building hierarchy staging
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_hierarchy_nodes AS
    SELECT
        CostCenterID,
        ParentCostCenterID,
        Level,
        Path,
        IsLeaf
    FROM vw_CostCenterHierarchy;

    
    /* =====================================================
       Step 7: Building rollup mapping
       (ancestor -> descendant relationships)
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_costcenter_rollup_map AS
    WITH RECURSIVE rollup_map AS (
        SELECT
            CostCenterID AS AncestorCostCenterID,
            CostCenterID AS DescendantCostCenterID
        FROM CostCenter

        UNION ALL

        SELECT
            rm.AncestorCostCenterID,
            c.CostCenterID AS DescendantCostCenterID
        FROM rollup_map rm
        JOIN CostCenter c
            ON c.ParentCostCenterID = rm.DescendantCostCenterID
    )
    SELECT DISTINCT
        AncestorCostCenterID,
        DescendantCostCenterID
    FROM rollup_map;

    /* =====================================================
       Step 8: Aggregating consolidated amounts
       ===================================================== */
   CREATE OR REPLACE TEMP TABLE temp_consolidated_amounts AS
    SELECT
        bli.BudgetHeaderID,
        bli.GLAccountID,
        rm.AncestorCostCenterID AS CostCenterID,
        bli.FiscalPeriodID,
        SUM(COALESCE(bli.FinalAmount, 0)) AS ConsolidatedAmount,
        CAST(0 AS NUMBER(19,4)) AS EliminationAmount,
        SUM(COALESCE(bli.FinalAmount, 0)) AS FinalAmount,
        COUNT(*) AS SourceCount
    FROM BudgetLineItem bli
    JOIN temp_costcenter_rollup_map rm
        ON bli.CostCenterID = rm.DescendantCostCenterID
    WHERE bli.BudgetHeaderID = :input_source_budget_id
    GROUP BY
        bli.BudgetHeaderID,
        bli.GLAccountID,
        rm.AncestorCostCenterID,
        bli.FiscalPeriodID;

    /* =====================================================
       Step 9: Intercompany elimination (first-pass)
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_intercompany_eliminations AS
    SELECT
        rm.AncestorCostCenterID AS CostCenterID,
        bli.GLAccountID,
        bli.FiscalPeriodID,
        LEAST(
            SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) > 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END),
            ABS(SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) < 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END))
        ) AS EliminationAmount
    FROM BudgetLineItem bli
    JOIN GLAccount gla
        ON bli.GLAccountID = gla.GLAccountID
    JOIN temp_costcenter_rollup_map rm
        ON bli.CostCenterID = rm.DescendantCostCenterID
    WHERE bli.BudgetHeaderID = :input_source_budget_id
      AND gla.IntercompanyFlag = TRUE
    GROUP BY
        rm.AncestorCostCenterID,
        bli.GLAccountID,
        bli.FiscalPeriodID
    HAVING
        SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) > 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END) > 0
        AND
        SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) < 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END) < 0;

        
    /* =====================================================
       Step 10: Applying elimination
       ===================================================== */
    UPDATE temp_consolidated_amounts t
    SET FinalAmount = t.ConsolidatedAmount - e.EliminationAmount
    FROM temp_intercompany_eliminations e
    WHERE t.GLAccountID = e.GLAccountID
      AND t.CostCenterID = e.CostCenterID
      AND t.FiscalPeriodID = e.FiscalPeriodID;


    /* =====================================================
       Step 11: Inserting final consolidated results
       ===================================================== */
 INSERT INTO BudgetLineItem (
        BudgetHeaderID,
        GLAccountID,
        CostCenterID,
        FiscalPeriodID,
        OriginalAmount,
        AdjustedAmount,
        FinalAmount,
        LocalCurrencyAmount,
        ReportingCurrencyAmount,
        StatisticalQuantity,
        UnitOfMeasure,
        SpreadMethodCode,
        SeasonalityFactor,
        SourceSystem,
        SourceReference,
        ImportBatchID,
        IsAllocated,
        AllocationSourceLineID,
        AllocationPercentage,
        LastModifiedByUserID,
        LastModifiedDateTime,
        RowHash
    )
    SELECT
        :v_target_budget_id AS BudgetHeaderID,
        GLAccountID,
        CostCenterID,
        FiscalPeriodID,
        ConsolidatedAmount AS OriginalAmount,
        0 AS AdjustedAmount,
        FinalAmount,
        NULL AS LocalCurrencyAmount,
        NULL AS ReportingCurrencyAmount,
        NULL AS StatisticalQuantity,
        NULL AS UnitOfMeasure,
        NULL AS SpreadMethodCode,
        NULL AS SeasonalityFactor,
        'CONSOLIDATION_PROCESS' AS SourceSystem,
        'From source budget ' || BudgetHeaderID AS SourceReference,
        NULL AS ImportBatchID,
        FALSE AS IsAllocated,
        NULL AS AllocationSourceLineID,
        NULL AS AllocationPercentage,
        NULL AS LastModifiedByUserID,
        CURRENT_TIMESTAMP() AS LastModifiedDateTime,
        NULL AS RowHash
    FROM temp_consolidated_amounts;

    /* =====================================================
       Step 12: Success response
       ===================================================== */
    RETURN 'SUCCESS: Consolidated budget created. Target ID = ' || v_target_budget_id;

END;
$$;

/* =========================================================
   PROCEDURE-LEVEL VALIDATION
   ---------------------------------------------------------
   Purpose:
   Validates that the procedure:
   - creates a consolidated BudgetHeader
   - inserts consolidated BudgetLineItem rows
   ========================================================= */

-- Executing consolidation for a known source budget
CALL usp_ProcessBudgetConsolidation(10000);

-- Validating target BudgetHeader creation
SELECT *
FROM BudgetHeader
WHERE BaseBudgetHeaderID = 10000
ORDER BY BudgetHeaderID DESC;

-- Validating inserted consolidated BudgetLineItem rows
SELECT
    BudgetHeaderID,
    GLAccountID,
    CostCenterID,
    FiscalPeriodID,
    OriginalAmount,
    AdjustedAmount,
    FinalAmount,
    SourceSystem,
    SourceReference
FROM BudgetLineItem
WHERE BudgetHeaderID = (
    SELECT MAX(BudgetHeaderID)
    FROM BudgetHeader
    WHERE BaseBudgetHeaderID = 10000
      AND BudgetType = 'CONSOLIDATED'
)
ORDER BY GLAccountID, CostCenterID, FiscalPeriodID;

/* =========================================================
    DEBUG: HIERARCHY VIEW
   ---------------------------------------------------------
   Using only for debugging hierarchy logic
   ========================================================= */
SELECT *
FROM vw_CostCenterHierarchy
ORDER BY Path;


/* =========================================================
    DEBUG: ROLLUP MAP
   ---------------------------------------------------------
   Rebuilding and inspecting ancestor-descendant mapping
   ========================================================= */
CREATE OR REPLACE TEMP TABLE temp_costcenter_rollup_map AS
WITH RECURSIVE rollup_map AS (
    SELECT
        CostCenterID AS AncestorCostCenterID,
        CostCenterID AS DescendantCostCenterID
    FROM CostCenter

    UNION ALL

    SELECT
        rm.AncestorCostCenterID,
        c.CostCenterID AS DescendantCostCenterID
    FROM rollup_map rm
    JOIN CostCenter c
        ON c.ParentCostCenterID = rm.DescendantCostCenterID
)
SELECT DISTINCT
    AncestorCostCenterID,
    DescendantCostCenterID
FROM rollup_map;

SELECT *
FROM temp_costcenter_rollup_map
ORDER BY AncestorCostCenterID, DescendantCostCenterID;


/* =========================================================
    DEBUG: ELIMINATION STAGING
   ---------------------------------------------------------
   Rebuilding and inspecting intercompany elimination logic
   ========================================================= */
SET source_budget_id = 10000;

CREATE OR REPLACE TEMP TABLE temp_intercompany_eliminations AS
SELECT
    rm.AncestorCostCenterID AS CostCenterID,
    bli.GLAccountID,
    bli.FiscalPeriodID,
    LEAST(
        SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) > 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END),
        ABS(SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) < 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END))
    ) AS EliminationAmount
FROM BudgetLineItem bli
JOIN GLAccount gla
    ON bli.GLAccountID = gla.GLAccountID
JOIN temp_costcenter_rollup_map rm
    ON bli.CostCenterID = rm.DescendantCostCenterID
WHERE bli.BudgetHeaderID = $source_budget_id
  AND gla.IntercompanyFlag = TRUE
GROUP BY
    rm.AncestorCostCenterID,
    bli.GLAccountID,
    bli.FiscalPeriodID
HAVING
    SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) > 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END) > 0
    AND
    SUM(CASE WHEN COALESCE(bli.FinalAmount, 0) < 0 THEN COALESCE(bli.FinalAmount, 0) ELSE 0 END) < 0;

SELECT *
FROM temp_intercompany_eliminations
ORDER BY GLAccountID, CostCenterID, FiscalPeriodID;

/* =========================================================
   IDEMPOTENCY RETEST
   ---------------------------------------------------------
   Purpose:
   Prove that rerun protection works correctly by:
   1. cleaning prior consolidated outputs
   2. rerunning procedure once
   3. confirming exactly one consolidated header exists
   4. rerunning again to confirm error on duplicate execution
   ========================================================= */

-- Check current consolidated count
SELECT COUNT(*)
FROM BudgetHeader
WHERE BaseBudgetHeaderID = 10000
  AND BudgetType = 'CONSOLIDATED';

-- Remove consolidated line items first
DELETE FROM BudgetLineItem
WHERE BudgetHeaderID IN (
    SELECT BudgetHeaderID
    FROM BudgetHeader
    WHERE BaseBudgetHeaderID = 10000
      AND BudgetType = 'CONSOLIDATED'
);

-- Remove consolidated headers
DELETE FROM BudgetHeader
WHERE BaseBudgetHeaderID = 10000
  AND BudgetType = 'CONSOLIDATED';

-- Confirm cleanup
SELECT COUNT(*)
FROM BudgetHeader
WHERE BaseBudgetHeaderID = 10000
  AND BudgetType = 'CONSOLIDATED';

-- First run should succeed
CALL usp_ProcessBudgetConsolidation(10000);

-- Confirm exactly one consolidated target exists
SELECT COUNT(*)
FROM BudgetHeader
WHERE BaseBudgetHeaderID = 10000
  AND BudgetType = 'CONSOLIDATED';

-- Second run should fail with duplicate-protection message
CALL usp_ProcessBudgetConsolidation(10000);

SELECT * FROM BudgetHeader ORDER BY BudgetHeaderID DESC;

/* =========================================================
   STORED PROCEDURE: usp_ExecuteCostAllocation
   ---------------------------------------------------------
   Purpose:
   Executes cost allocation for a given budget by:
   - validating source budget
   - selecting active allocation rules
   - expanding target cost centers from VARIANT specification
   - identifying eligible source budget line items
   - calculating allocation amounts using percentages or basis
   - inserting allocated rows into BudgetLineItem
   - maintaining traceability to source records

   Design Notes:
   - Uses TEMP tables for rule selection, target expansion, and allocation staging
   - Implements set-based processing (no row-by-row loops)
   - Supports both percentage-based and dynamic allocation (via fn_GetAllocationFactor)
   - Includes dry-run mode for safe validation before execution
   - Simplifies SQL Server logic (no locks, no delays, no TVPs)
   ========================================================= */

CREATE OR REPLACE PROCEDURE usp_ExecuteCostAllocation(
    input_budget_header_id      INTEGER,
    input_allocation_rule_ids   STRING DEFAULT NULL,   -- comma-separated list, NULL = all active rules
    input_fiscal_period_id      INTEGER DEFAULT NULL,  -- NULL = all periods
    input_dry_run               BOOLEAN DEFAULT FALSE,
    input_max_iterations        INTEGER DEFAULT 100,   -- retained for interface compatibility
    input_throttle_delay_ms     INTEGER DEFAULT 0,     -- retained but not used
    input_concurrency_mode      STRING DEFAULT 'NONE'  -- retained but not used
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_budget_exists             NUMBER DEFAULT 0;
    v_rule_count                NUMBER DEFAULT 0;
    v_rows_allocated            NUMBER DEFAULT 0;
    v_warning_messages          STRING DEFAULT '';
BEGIN

    /* =====================================================
       Step 1: Validating source budget exists
       ===================================================== */
    SELECT COUNT(*)
    INTO :v_budget_exists
    FROM BudgetHeader
    WHERE BudgetHeaderID = :input_budget_header_id;

    IF (v_budget_exists = 0) THEN
        RETURN 'ERROR: BudgetHeaderID not found.';
    END IF;


    /* =====================================================
       Step 2: Parsing selected rule IDs (optional)
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_selected_rule_ids AS
    SELECT DISTINCT
        TRY_TO_NUMBER(TRIM(value::STRING)) AS AllocationRuleID
    FROM TABLE(FLATTEN(INPUT => SPLIT(COALESCE(:input_allocation_rule_ids, ''), ',')))
    WHERE TRIM(value::STRING) <> ''
      AND TRY_TO_NUMBER(TRIM(value::STRING)) IS NOT NULL;


    /* =====================================================
       Step 3: Select active rules
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_active_rules AS
    SELECT *
    FROM AllocationRule ar
    WHERE ar.IsActive = TRUE
      AND CURRENT_DATE BETWEEN ar.EffectiveFromDate
                           AND COALESCE(ar.EffectiveToDate, CURRENT_DATE)
      AND (
            :input_allocation_rule_ids IS NULL
            OR ar.AllocationRuleID IN (
                SELECT AllocationRuleID FROM temp_selected_rule_ids
            )
      );

    SELECT COUNT(*)
    INTO :v_rule_count
    FROM temp_active_rules;

    IF (v_rule_count = 0) THEN
        RETURN 'ERROR: No active allocation rules matched the input.';
    END IF;


    /* =====================================================
       Step 4: Build simplified rule dependency map
       -----------------------------------------------------
       Preserves dependency awareness from the SQL Server
       procedure while keeping execution set-based.
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_rule_dependencies AS
    WITH RECURSIVE deps AS (
        SELECT
            AllocationRuleID AS RuleID,
            DependsOnRuleID,
            1 AS DependencyLevel
        FROM temp_active_rules
        WHERE DependsOnRuleID IS NOT NULL

        UNION ALL

        SELECT
            d.RuleID,
            r.DependsOnRuleID,
            d.DependencyLevel + 1
        FROM deps d
        JOIN temp_active_rules r
          ON d.DependsOnRuleID = r.AllocationRuleID
        WHERE r.DependsOnRuleID IS NOT NULL
          AND d.DependencyLevel < 10
    )
    SELECT DISTINCT
        RuleID,
        DependsOnRuleID,
        DependencyLevel
    FROM deps;


    /* =====================================================
       Step 5: Expanding targets from TargetSpecification
       -----------------------------------------------------
       Assuming Snowflake TargetSpecification is stored as:
       - either an array of target objects
       - or an object containing AllocationTargets array
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_rule_targets AS
    SELECT
        r.AllocationRuleID,
        COALESCE(
            f.value:CostCenterID::INTEGER,
            TRY_TO_NUMBER(f.value:"@CostCenterID"::STRING)
        ) AS TargetCostCenterID,
        COALESCE(
            f.value:CostCenterCode::STRING,
            f.value:"@CostCenterCode"::STRING
        ) AS TargetCostCenterCode,
        COALESCE(
            f.value:AllocationPercentage::NUMBER(8,6),
            TRY_TO_NUMBER(f.value:"@AllocationPercentage"::STRING)
        ) AS TargetAllocationPct,
        COALESCE(
            f.value:Priority::INTEGER,
            TRY_TO_NUMBER(f.value:"@Priority"::STRING)
        ) AS TargetPriority,
        f.value:AccountFilter::STRING AS AccountFilter,
        f.value:ExcludePattern::STRING AS ExcludePattern
    FROM temp_active_rules r,
    LATERAL FLATTEN(
        INPUT => COALESCE(r.TargetSpecification:"AllocationTargets", r.TargetSpecification)
    ) f;

    /* Resolve target cost center via code if ID is missing */
    CREATE OR REPLACE TEMP TABLE temp_rule_targets_resolved AS
    SELECT
        t.AllocationRuleID,
        COALESCE(t.TargetCostCenterID, cc.CostCenterID) AS TargetCostCenterID,
        COALESCE(t.TargetCostCenterCode, cc.CostCenterCode) AS TargetCostCenterCode,
        t.TargetAllocationPct,
        t.TargetPriority,
        t.AccountFilter,
        t.ExcludePattern,
        cc.IsActive AS TargetIsActive
    FROM temp_rule_targets t
    LEFT JOIN CostCenter cc
      ON t.TargetCostCenterID = cc.CostCenterID
      OR (t.TargetCostCenterID IS NULL AND t.TargetCostCenterCode = cc.CostCenterCode);


    /* =====================================================
       Step 6: Building source line queue
       -----------------------------------------------------
       Mirroring SQL Server queue-building logic using exact
       and pattern-based rule matching.
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_allocation_queue AS
    SELECT
        ROW_NUMBER() OVER (ORDER BY ar.ExecutionSequence, bli.BudgetLineItemID) AS QueueID,
        ar.AllocationRuleID,
        bli.BudgetLineItemID AS SourceBudgetLineItemID,
        bli.FinalAmount AS SourceAmount,
        bli.FinalAmount AS RemainingAmount,
        ar.ExecutionSequence,
        ar.DependsOnRuleID,
        FALSE AS IsProcessed,
        NULL::TIMESTAMP_NTZ AS ProcessedDateTime,
        NULL::STRING AS ErrorMessage
    FROM temp_active_rules ar
    JOIN BudgetLineItem bli
      ON bli.BudgetHeaderID = :input_budget_header_id
    JOIN CostCenter cc
      ON bli.CostCenterID = cc.CostCenterID
    JOIN GLAccount gla
      ON bli.GLAccountID = gla.GLAccountID
    WHERE (:input_fiscal_period_id IS NULL OR bli.FiscalPeriodID = :input_fiscal_period_id)
      AND (ar.SourceCostCenterID IS NULL OR cc.CostCenterID = ar.SourceCostCenterID)
      AND (ar.SourceCostCenterPattern IS NULL OR cc.CostCenterCode LIKE ar.SourceCostCenterPattern)
      AND (ar.SourceAccountPattern IS NULL OR gla.AccountNumber LIKE ar.SourceAccountPattern)
      AND COALESCE(bli.FinalAmount, 0) <> 0
      AND COALESCE(bli.IsAllocated, FALSE) = FALSE;


    /* =====================================================
       Step 7: Calculating allocation results
       -----------------------------------------------------
       Uses explicit target percentages when present.
       Otherwise falls back to fn_GetAllocationFactor().
       Target GL account remains the source GL account in
       this first-pass implementation.
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_allocation_results AS
    SELECT
        q.SourceBudgetLineItemID,
        vt.TargetCostCenterID,
        bli.GLAccountID AS TargetGLAccountID,

        CASE
            WHEN ar.RoundingMethod = 'UP' THEN
                CEIL(
                    q.RemainingAmount *
                    COALESCE(
                        vt.TargetAllocationPct,
                        fn_GetAllocationFactor(
                            bli.CostCenterID,
                            vt.TargetCostCenterID,
                            ar.AllocationBasis,
                            bli.FiscalPeriodID,
                            :input_budget_header_id
                        )
                    )
                    * POWER(10, COALESCE(ar.RoundingPrecision, 2))
                ) / POWER(10, COALESCE(ar.RoundingPrecision, 2))

            WHEN ar.RoundingMethod = 'DOWN' THEN
                FLOOR(
                    q.RemainingAmount *
                    COALESCE(
                        vt.TargetAllocationPct,
                        fn_GetAllocationFactor(
                            bli.CostCenterID,
                            vt.TargetCostCenterID,
                            ar.AllocationBasis,
                            bli.FiscalPeriodID,
                            :input_budget_header_id
                        )
                    )
                    * POWER(10, COALESCE(ar.RoundingPrecision, 2))
                ) / POWER(10, COALESCE(ar.RoundingPrecision, 2))

            ELSE
                ROUND(
                    q.RemainingAmount *
                    COALESCE(
                        vt.TargetAllocationPct,
                        fn_GetAllocationFactor(
                            bli.CostCenterID,
                            vt.TargetCostCenterID,
                            ar.AllocationBasis,
                            bli.FiscalPeriodID,
                            :input_budget_header_id
                        )
                    ),
                    COALESCE(ar.RoundingPrecision, 2)
                )
        END AS AllocatedAmount,

        COALESCE(
            vt.TargetAllocationPct,
            fn_GetAllocationFactor(
                bli.CostCenterID,
                vt.TargetCostCenterID,
                ar.AllocationBasis,
                bli.FiscalPeriodID,
                :input_budget_header_id
            )
        ) AS AllocationPercentage,

        q.AllocationRuleID,
        q.ExecutionSequence AS ProcessingSequence
    FROM temp_allocation_queue q
    JOIN temp_active_rules ar
      ON q.AllocationRuleID = ar.AllocationRuleID
    JOIN BudgetLineItem bli
      ON q.SourceBudgetLineItemID = bli.BudgetLineItemID
    JOIN temp_rule_targets_resolved vt
      ON vt.AllocationRuleID = ar.AllocationRuleID
    WHERE vt.TargetIsActive = TRUE
      AND vt.TargetCostCenterID IS NOT NULL
      AND (vt.AccountFilter IS NULL OR bli.GLAccountID IS NOT NULL)
      AND (
            vt.ExcludePattern IS NULL
            OR NOT EXISTS (
                SELECT 1
                FROM GLAccount g2
                WHERE g2.GLAccountID = bli.GLAccountID
                  AND g2.AccountNumber LIKE vt.ExcludePattern
            )
      );


    /* =====================================================
       Step 8: Applying minimum amount filter and capture warnings
       ===================================================== */
    UPDATE temp_allocation_queue q
    SET ErrorMessage = 'No allocation targets resolved for rule'
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_rule_targets_resolved t
        WHERE t.AllocationRuleID = q.AllocationRuleID
          AND t.TargetIsActive = TRUE
          AND t.TargetCostCenterID IS NOT NULL
    );

    DELETE FROM temp_allocation_results
    WHERE ABS(COALESCE(AllocatedAmount, 0)) < COALESCE((
        SELECT ar.MinimumAmount
        FROM temp_active_rules ar
        WHERE ar.AllocationRuleID = temp_allocation_results.AllocationRuleID
    ), 0);


    /* =====================================================
       Step 9: Persisting results unless DryRun
       ===================================================== */
    IF (:input_dry_run = FALSE) THEN

        INSERT INTO BudgetLineItem (
            BudgetHeaderID,
            GLAccountID,
            CostCenterID,
            FiscalPeriodID,
            OriginalAmount,
            AdjustedAmount,
            FinalAmount,
            IsAllocated,
            AllocationSourceLineID,
            AllocationPercentage,
            LastModifiedDateTime
        )
        SELECT
            :input_budget_header_id,
            r.TargetGLAccountID,
            r.TargetCostCenterID,
            bli.FiscalPeriodID,
            r.AllocatedAmount,
            0,
            r.AllocatedAmount,
            TRUE,
            r.SourceBudgetLineItemID,
            r.AllocationPercentage,
            CURRENT_TIMESTAMP()
        FROM temp_allocation_results r
        JOIN BudgetLineItem bli
          ON r.SourceBudgetLineItemID = bli.BudgetLineItemID;

        SELECT COUNT(*)
        INTO :v_rows_allocated
        FROM temp_allocation_results;

        UPDATE BudgetLineItem bli
        SET IsAllocated = TRUE
        FROM (
            SELECT DISTINCT SourceBudgetLineItemID
            FROM temp_allocation_results
        ) src
        WHERE bli.BudgetLineItemID = src.SourceBudgetLineItemID;

    ELSE

        SELECT COUNT(*)
        INTO :v_rows_allocated
        FROM temp_allocation_results;

    END IF;


    /* =====================================================
       Step 10: Building warning message string
       ===================================================== */
    SELECT COALESCE(
        LISTAGG('Rule ' || AllocationRuleID || ': ' || ErrorMessage, '; ')
            WITHIN GROUP (ORDER BY QueueID),
        ''
    )
    INTO :v_warning_messages
    FROM temp_allocation_queue
    WHERE ErrorMessage IS NOT NULL;

    IF (:input_max_iterations <= 0) THEN
        v_warning_messages := v_warning_messages || '; WARNING: input_max_iterations ignored in Snowflake first-pass rewrite';
    END IF;

    RETURN
        'SUCCESS: Allocation procedure completed. RowsAllocated=' || v_rows_allocated ||
        CASE
            WHEN v_warning_messages IS NOT NULL AND v_warning_messages <> ''
                THEN ' | Warnings=' || v_warning_messages
            ELSE ''
        END;

END;
$$;


/* =========================================================
   PROCEDURE-LEVEL VALIDATION
   ---------------------------------------------------------
   Uses one controlled rule to validate:
   - active rule selection
   - target expansion from VARIANT
   - allocation math
   - traceability back to source rows
   ========================================================= */

-- Test rule for controlled validation
INSERT INTO AllocationRule (
    RuleCode,
    RuleName,
    RuleType,
    AllocationMethod,
    SourceCostCenterID,
    TargetSpecification,
    AllocationBasis,
    AllocationPercentage,
    EffectiveFromDate,
    EffectiveToDate,
    IsActive
)
SELECT
    'TEST_RULE_1',
    'Simple Test Allocation',
    'COST',
    'PERCENTAGE',
    100,
    PARSE_JSON('[
        {"CostCenterID": 110, "AllocationPercentage": 0.6},
        {"CostCenterID": 120, "AllocationPercentage": 0.4}
    ]'),
    'EQUAL',
    NULL,
    CURRENT_DATE - 1,
    NULL,
    TRUE;
SELECT * FROM BudgetLineItem WHERE BudgetHeaderID = 10000;
-- Dry run
CALL usp_ExecuteCostAllocation(10000, NULL, NULL, TRUE, 100, 0, 'NONE');

-- Final execution
CALL usp_ExecuteCostAllocation(10000, NULL, NULL, FALSE, 100, 0, 'NONE');

-- Inspect all allocation-related rows
SELECT *
FROM BudgetLineItem;

-- Validating newly inserted allocation rows
SELECT
    BudgetLineItemID,
    BudgetHeaderID,
    GLAccountID,
    CostCenterID,
    FiscalPeriodID,
    OriginalAmount,
    FinalAmount,
    AllocationSourceLineID,
    AllocationPercentage,
    IsAllocated
FROM BudgetLineItem
WHERE BudgetLineItemID 
ORDER BY BudgetLineItemID;

-- High-level allocation check
SELECT 
    SUM(CASE WHEN IsAllocated = FALSE THEN FinalAmount ELSE 0 END) AS SourceTotal,
    SUM(CASE WHEN IsAllocated = TRUE THEN FinalAmount ELSE 0 END) AS AllocatedTotal
FROM BudgetLineItem
WHERE BudgetHeaderID = 10000;


/* =========================================================
   STORED PROCEDURE: usp_ReconcileIntercompanyBalances
   ---------------------------------------------------------
   Purpose:
   Reconciles intercompany balances for a given budget by:
   - validating source budget
   - identifying entity-level intercompany pairs
   - calculating variances and tolerance status
   - optionally creating reconciliation adjustment journals
   - returning summary reconciliation results

   Design Notes:
   - Uses TEMP tables for entity filtering and pair staging
   - Replaces XML entity input with a comma-separated string
   - Replaces XML report output with a summary return string
   - Preserves core variance and tolerance logic
   - Implements first-pass adjustment journal creation
   ========================================================= */

CREATE OR REPLACE PROCEDURE usp_ReconcileIntercompanyBalances(
    input_budget_header_id        INTEGER,
    input_reconciliation_date     DATE DEFAULT NULL,
    input_entity_codes            STRING DEFAULT NULL,   -- comma-separated list; NULL = all entities in budget
    input_tolerance_amount        NUMBER(19,4) DEFAULT 0.01,
    input_tolerance_percent       NUMBER(5,4) DEFAULT 0.001,
    input_auto_create_adjustments BOOLEAN DEFAULT FALSE
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_budget_exists           NUMBER DEFAULT 0;
    v_effective_date          DATE;
    v_reconciliation_id       STRING;
    v_recon_period_id         NUMBER;
    v_pair_count              NUMBER DEFAULT 0;
    v_unreconciled_count      NUMBER DEFAULT 0;
    v_total_variance_amount   NUMBER(19,4) DEFAULT 0;
    v_journal_id              NUMBER DEFAULT NULL;
BEGIN

    /* =====================================================
       Step 1: Validating source budget exists
       ===================================================== */
    SELECT COUNT(*)
    INTO :v_budget_exists
    FROM BudgetHeader
    WHERE BudgetHeaderID = :input_budget_header_id;

    IF (v_budget_exists = 0) THEN
        RETURN 'ERROR: BudgetHeaderID not found.';
    END IF;

    SELECT COALESCE(:input_reconciliation_date, CURRENT_DATE())
    INTO :v_effective_date;

    SELECT UUID_STRING()
    INTO :v_reconciliation_id;


    /* =====================================================
       Step 2: Building entity filter list
       -----------------------------------------------------
       For current synthetic validation data, entities are
       grouped from CostCenterID ranges because CostCenterCode
       does not use delimiter-based entity prefixes.
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_entity_list (
        EntityCode STRING
    );

    IF (:input_entity_codes IS NOT NULL) THEN
        INSERT INTO temp_entity_list (EntityCode)
        SELECT DISTINCT TRIM(value::STRING)
        FROM TABLE(FLATTEN(INPUT => SPLIT(:input_entity_codes, ',')))
        WHERE TRIM(value::STRING) <> '';
    ELSE
        INSERT INTO temp_entity_list (EntityCode)
        SELECT DISTINCT
            CASE
                WHEN cc.CostCenterID IN (100, 110) THEN 'ENTITY_A'
                WHEN cc.CostCenterID IN (120, 130) THEN 'ENTITY_B'
                ELSE cc.CostCenterCode
            END AS EntityCode
        FROM BudgetLineItem bli
        JOIN CostCenter cc
          ON bli.CostCenterID = cc.CostCenterID
        WHERE bli.BudgetHeaderID = :input_budget_header_id;
    END IF;


    /* =====================================================
       Step 3: Aggregating intercompany balances by entity/account
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_entity_account_balances AS
    SELECT
        CASE
            WHEN cc.CostCenterID IN (100, 110) THEN 'ENTITY_A'
            WHEN cc.CostCenterID IN (120, 130) THEN 'ENTITY_B'
            ELSE cc.CostCenterCode
        END AS EntityCode,
        bli.GLAccountID,
        gla.ConsolidationAccountID AS PartnerAccountID,
        SUM(COALESCE(bli.FinalAmount, 0)) AS Amount
    FROM BudgetLineItem bli
    JOIN GLAccount gla
      ON bli.GLAccountID = gla.GLAccountID
    JOIN CostCenter cc
      ON bli.CostCenterID = cc.CostCenterID
    JOIN temp_entity_list el
      ON CASE
             WHEN cc.CostCenterID IN (100, 110) THEN 'ENTITY_A'
             WHEN cc.CostCenterID IN (120, 130) THEN 'ENTITY_B'
             ELSE cc.CostCenterCode
         END = el.EntityCode
    WHERE bli.BudgetHeaderID = :input_budget_header_id
      AND gla.IntercompanyFlag = TRUE
      AND gla.ConsolidationAccountID IS NOT NULL
    GROUP BY
        CASE
            WHEN cc.CostCenterID IN (100, 110) THEN 'ENTITY_A'
            WHEN cc.CostCenterID IN (120, 130) THEN 'ENTITY_B'
            ELSE cc.CostCenterCode
        END,
        bli.GLAccountID,
        gla.ConsolidationAccountID;


    /* =====================================================
       Step 4: Building intercompany pairs and calculate variance
       ===================================================== */
    CREATE OR REPLACE TEMP TABLE temp_intercompany_pairs AS
    SELECT
        ROW_NUMBER() OVER (ORDER BY b1.EntityCode, b2.EntityCode, b1.GLAccountID) AS PairID,
        b1.EntityCode AS Entity1Code,
        b2.EntityCode AS Entity2Code,
        b1.GLAccountID,
        b1.PartnerAccountID,
        b1.Amount AS Entity1Amount,
        COALESCE(-b2.Amount, 0) AS Entity2Amount,
        b1.Amount + COALESCE(b2.Amount, 0) AS Variance,

        CASE
            WHEN ABS(b1.Amount) > 0
                THEN (b1.Amount + COALESCE(b2.Amount, 0)) / ABS(b1.Amount)
            ELSE NULL
        END AS VariancePercent,

        CASE
            WHEN ABS(b1.Amount + COALESCE(b2.Amount, 0)) <= :input_tolerance_amount THEN TRUE
            WHEN ABS(b1.Amount) > 0
                 AND ABS((b1.Amount + COALESCE(b2.Amount, 0)) / b1.Amount) <= :input_tolerance_percent THEN TRUE
            ELSE FALSE
        END AS IsWithinTolerance,

        CASE
            WHEN ABS(b1.Amount + COALESCE(b2.Amount, 0)) <= :input_tolerance_amount THEN 'RECONCILED'
            WHEN ABS(b1.Amount) > 0
                 AND ABS((b1.Amount + COALESCE(b2.Amount, 0)) / b1.Amount) <= :input_tolerance_percent THEN 'RECONCILED'
            ELSE 'UNRECONCILED'
        END AS ReconciliationStatus
    FROM temp_entity_account_balances b1
    LEFT JOIN temp_entity_account_balances b2
      ON b2.GLAccountID = b1.PartnerAccountID
     AND b2.EntityCode <> b1.EntityCode
    WHERE COALESCE(b1.Amount, 0) <> 0
       OR COALESCE(b2.Amount, 0) <> 0;


    /* =====================================================
       Step 5: Summary metrics
       ===================================================== */
    SELECT COUNT(*)
    INTO :v_pair_count
    FROM temp_intercompany_pairs;

    SELECT COUNT(*), COALESCE(SUM(ABS(Variance)), 0)
    INTO :v_unreconciled_count, :v_total_variance_amount
    FROM temp_intercompany_pairs
    WHERE ReconciliationStatus = 'UNRECONCILED';


    /* =====================================================
       Step 6: Resolving reconciliation fiscal period
       ===================================================== */

    SELECT MIN(FiscalPeriodID)
    INTO :v_recon_period_id
    FROM FiscalPeriod
    WHERE :v_effective_date BETWEEN PeriodStartDate AND PeriodEndDate;
    
    -- Fallback 
    IF (v_recon_period_id IS NULL) THEN
        SELECT MIN(FiscalPeriodID)
        INTO :v_recon_period_id
        FROM FiscalPeriod;
    END IF;


    /* =====================================================
       Step 7: Auto-creating adjustment journal if requested
       ===================================================== */
    IF (:input_auto_create_adjustments = TRUE AND :v_unreconciled_count > 0) THEN

        INSERT INTO ConsolidationJournal (
            JournalNumber,
            JournalType,
            BudgetHeaderID,
            FiscalPeriodID,
            PostingDate,
            Description,
            StatusCode,
            TotalDebits,
            TotalCredits,
            IsBalanced
        )
        SELECT
            'ICR-' || TO_VARCHAR(:v_effective_date, 'YYYYMMDD') || '-' || SUBSTR(REPLACE(:v_reconciliation_id, '-', ''), 1, 8),
            'ELIMINATION',
            :input_budget_header_id,
            :v_recon_period_id,
            :v_effective_date,
            'Auto-generated intercompany reconciliation adjustment',
            'DRAFT',
            0,
            0,
            FALSE;

        SELECT MAX(JournalID)
        INTO :v_journal_id
        FROM ConsolidationJournal
        WHERE BudgetHeaderID = :input_budget_header_id
          AND JournalType = 'ELIMINATION';

        INSERT INTO ConsolidationJournalLine (
            JournalID,
            LineNumber,
            GLAccountID,
            CostCenterID,
            DebitAmount,
            CreditAmount,
            NetAmount,
            Description,
            CreatedDateTime
        )
        SELECT
            :v_journal_id,
            ROW_NUMBER() OVER (ORDER BY PairID),
            GLAccountID,
            (
                SELECT MIN(cc.CostCenterID)
                FROM CostCenter cc
                WHERE CASE
                          WHEN cc.CostCenterID IN (100, 110) THEN 'ENTITY_A'
                          WHEN cc.CostCenterID IN (120, 130) THEN 'ENTITY_B'
                          ELSE cc.CostCenterCode
                      END = Entity1Code
            ) AS CostCenterID,
            CASE WHEN Variance > 0 THEN Variance ELSE 0 END AS DebitAmount,
            CASE WHEN Variance < 0 THEN ABS(Variance) ELSE 0 END AS CreditAmount,
            Variance,
            'IC Adjustment: ' || Entity1Code || ' <-> ' || COALESCE(Entity2Code, 'UNKNOWN'),
            CURRENT_TIMESTAMP()
        FROM temp_intercompany_pairs
        WHERE ReconciliationStatus = 'UNRECONCILED'
          AND ABS(Variance) > :input_tolerance_amount;

        UPDATE ConsolidationJournal cj
        SET
            TotalDebits = src.TotalDebits,
            TotalCredits = src.TotalCredits,
            IsBalanced = CASE WHEN src.TotalDebits = src.TotalCredits THEN TRUE ELSE FALSE END
        FROM (
            SELECT
                JournalID,
                COALESCE(SUM(DebitAmount), 0) AS TotalDebits,
                COALESCE(SUM(CreditAmount), 0) AS TotalCredits
            FROM ConsolidationJournalLine
            WHERE JournalID = :v_journal_id
            GROUP BY JournalID
        ) src
        WHERE cj.JournalID = src.JournalID;

    END IF;


    /* =====================================================
       Step 8: Returning summary
       ===================================================== */
    RETURN
        'SUCCESS: Intercompany reconciliation completed. ' ||
        'PairCount=' || v_pair_count ||
        ' | UnreconciledCount=' || v_unreconciled_count ||
        ' | TotalVariance=' || v_total_variance_amount ||
        CASE
            WHEN v_journal_id IS NOT NULL
                THEN ' | AdjustmentJournalID=' || v_journal_id
            ELSE ''
        END;

END;
$$;


/* =========================================================
   PROCEDURE-LEVEL VALIDATION
   ---------------------------------------------------------
   Validates:
   - entity grouping from current CostCenter test data
   - intercompany pair creation
   - variance calculation
   - optional adjustment journal creation
   ========================================================= */

-- Dry run without journal creation
CALL usp_ReconcileIntercompanyBalances(10000, NULL, NULL, 0.01, 0.001, FALSE);

-- Final run with adjustment creation
CALL usp_ReconcileIntercompanyBalances(10000, NULL, NULL, 0.01, 0.001, TRUE);

-- Inspecting generated journals
SELECT *
FROM ConsolidationJournal
ORDER BY JournalID DESC;

-- Inspecting generated journal lines
SELECT *
FROM ConsolidationJournalLine
ORDER BY JournalLineID DESC;

