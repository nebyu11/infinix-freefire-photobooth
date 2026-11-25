/* ===========================================================================
   04_abac.sql  -  Attribute-Based Access Control (ABAC)
                   implemented with Row-Level Security + Dynamic Data Masking
   ---------------------------------------------------------------------------
   Run as : administrator, after 03. Safe to run again (idempotent).

   HONEST NOTE: SQL Server has no feature literally called "ABAC".
   We build ABAC from two native features:

   1. ROW-LEVEL SECURITY (RLS): a security policy calls a predicate function
      for every row. The function compares ATTRIBUTES and returns "allowed"
      or not. Attributes used here:
        - user attributes    : Staff.Department, Staff.Region, Staff.IsActive
                               (looked up from the connected database user)
        - resource attribute : Orders.ShipRegion, Customers.Region
        - session attribute  : SESSION_CONTEXT('CustomerID'), set by the
                               website right after a customer logs in
      Rule in plain English:
        admin / auditor                      -> every row
        active Sales or Support staff        -> rows where row.Region =
                                                staff.Region (or staff 'ALL')
        website (customer_role)              -> only rows of the logged-in
                                                customer (session attribute)
        anyone else                          -> no rows
   2. DYNAMIC DATA MASKING (DDM): hides parts of a column (email, phone) from
      users who lack the UNMASK permission. Data on disk is NOT changed.

   RBAC (03) answers "which TABLES/COLUMNS may this role touch?"
   ABAC (04) answers "which ROWS may this person see, given their attributes?"
   =========================================================================== */

SET NOCOUNT ON;
USE ShopDB;
GO

/* ---------------------------------------------------------------------------
   0. Clean re-run: the policy must be dropped before its function changes
   --------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'ShopAccessPolicy')
    DROP SECURITY POLICY sec.ShopAccessPolicy;
IF OBJECT_ID(N'sec.fn_AccessPredicate', N'IF') IS NOT NULL
    DROP FUNCTION sec.fn_AccessPredicate;
GO
-- Separate schema for security objects; normal users get no rights on it
IF SCHEMA_ID(N'sec') IS NULL EXEC (N'CREATE SCHEMA sec AUTHORIZATION dbo');
GO

/* ---------------------------------------------------------------------------
   1. PREDICATE FUNCTION (the ABAC rule)
   Inline table-valued function: returns one row (= allowed) or no row
   (= hidden). SCHEMABINDING is required by RLS and stops anyone from
   changing the referenced tables in a way that would break the rule.
   --------------------------------------------------------------------------- */
CREATE FUNCTION sec.fn_AccessPredicate
(
    @RowRegion     NVARCHAR(30),   -- resource attribute (region of the row)
    @RowCustomerID INT             -- resource attribute (owner of the row)
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS AccessGranted
    WHERE
        -- (a) administrators and auditors see everything
           IS_MEMBER(N'admin_role')   = 1
        OR IS_MEMBER(N'auditor_role') = 1
        OR IS_MEMBER(N'db_owner')     = 1      -- the DBA running these scripts
        -- (b) staff: attributes come from the Staff table of the connected user
        OR EXISTS (SELECT 1
                   FROM dbo.Staff AS s
                   WHERE s.DbUserName = USER_NAME()           -- who is asking
                     AND s.IsActive   = 1                     -- attribute: active?
                     AND s.Department IN (N'Sales', N'Support') -- attribute: department
                     AND (s.Region = N'ALL' OR s.Region = @RowRegion)) -- attribute: region
        -- (c) website: the row must belong to the customer stored in the
        --     session context by the app after login
        OR (    IS_MEMBER(N'customer_role') = 1
            AND @RowCustomerID = CAST(SESSION_CONTEXT(N'CustomerID') AS INT));
GO

/* ---------------------------------------------------------------------------
   2. SECURITY POLICY: attach the function to the tables
     FILTER predicate : silently hides rows on SELECT / UPDATE / DELETE
     BLOCK  predicate : REJECTS inserts/updates that would create a row the
                        user is not allowed to see (e.g. the website placing
                        an order for a different customer)
   --------------------------------------------------------------------------- */
CREATE SECURITY POLICY sec.ShopAccessPolicy
    ADD FILTER PREDICATE sec.fn_AccessPredicate(ShipRegion, CustomerID) ON dbo.Orders,
    ADD BLOCK  PREDICATE sec.fn_AccessPredicate(ShipRegion, CustomerID) ON dbo.Orders AFTER INSERT,
    ADD BLOCK  PREDICATE sec.fn_AccessPredicate(ShipRegion, CustomerID) ON dbo.Orders AFTER UPDATE,
    ADD FILTER PREDICATE sec.fn_AccessPredicate(Region, CustomerID)     ON dbo.Customers
WITH (STATE = ON);
GO
PRINT 'Row-Level Security policy sec.ShopAccessPolicy is ON (Orders, Customers).';
GO

/* ---------------------------------------------------------------------------
   3. DYNAMIC DATA MASKING on customer contact data
      email()            -> sXXX@XXXX.com
      partial(4,"..",3)  -> keep first 4 and last 3 characters
   --------------------------------------------------------------------------- */
ALTER TABLE dbo.Customers ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE dbo.Customers ALTER COLUMN Phone ADD MASKED WITH (FUNCTION = 'partial(4,"XXXXXX",3)');

-- Who may see the REAL values? Only those who must contact customers.
GRANT UNMASK ON dbo.Customers TO admin_role;
GRANT UNMASK ON dbo.Customers TO sales_role;
-- support_role and auditor_role do NOT get UNMASK -> they see masked values
PRINT 'Dynamic Data Masking on Customers.Email and Customers.Phone (UNMASK: admin, sales).';
GO

/* ===========================================================================
   DEMO: the SAME query run by different users returns different
   ROWS (RLS) and different COLUMN VALUES (masking).
   =========================================================================== */
PRINT '';
PRINT '=== DEMO 1: SELECT * FROM Orders - how many rows does each user see? ===';
IF OBJECT_ID(N'tempdb..#Seen') IS NOT NULL DROP TABLE #Seen;
CREATE TABLE #Seen (DbUser SYSNAME, Attributes NVARCHAR(60), OrdersSeen INT, RegionsSeen NVARCHAR(200));

DECLARE @u SYSNAME, @cnt INT, @regions NVARCHAR(200);
DECLARE d CURSOR LOCAL FAST_FORWARD FOR
    SELECT v.u FROM (VALUES (N'shop_admin'),(N'auditor_meron'),(N'sales_addis'),
                            (N'sales_hawassa'),(N'support_dawit')) v(u);
OPEN d; FETCH NEXT FROM d INTO @u;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXECUTE AS USER = @u;
        SELECT @cnt = COUNT(*) FROM dbo.Orders;
        SELECT @regions = STRING_AGG(ShipRegion, N', ') WITHIN GROUP (ORDER BY ShipRegion)
        FROM (SELECT DISTINCT ShipRegion FROM dbo.Orders) AS r;
    REVERT;
    INSERT #Seen
    SELECT @u, ISNULL(s.Department + N' / ' + s.Region, N'-'), @cnt, ISNULL(@regions, N'(none)')
    FROM (SELECT 1 AS x) AS one LEFT JOIN dbo.Staff AS s ON s.DbUserName = @u;
    FETCH NEXT FROM d INTO @u;
END
CLOSE d; DEALLOCATE d;
SELECT DbUser, Attributes AS [Department / Region], OrdersSeen, RegionsSeen FROM #Seen;
GO

PRINT '=== DEMO 2: SELECT customers - sales_addis (unmasked, Addis only) ===';
EXECUTE AS USER = N'sales_addis';
    SELECT CustomerID, FirstName, Email, Phone, Region FROM dbo.Customers ORDER BY CustomerID;
REVERT;
GO
PRINT '=== DEMO 2: SAME query - support_dawit (all regions, MASKED) ===';
EXECUTE AS USER = N'support_dawit';
    SELECT CustomerID, FirstName, Email, Phone, Region FROM dbo.Customers ORDER BY CustomerID;
REVERT;
GO

PRINT '=== DEMO 3: change an ATTRIBUTE, not a role ===';
PRINT 'Abebe (sales_addis) is moved to the Hawassa branch: only Staff.Region changes.';
UPDATE dbo.Staff SET Region = N'Hawassa' WHERE DbUserName = N'sales_addis';
EXECUTE AS USER = N'sales_addis';
    SELECT OrderID, ShipRegion, Status FROM dbo.Orders ORDER BY OrderID;
REVERT;
PRINT 'Abebe is deactivated (IsActive = 0): he immediately sees nothing.';
UPDATE dbo.Staff SET IsActive = 0 WHERE DbUserName = N'sales_addis';
EXECUTE AS USER = N'sales_addis';
    SELECT COUNT(*) AS OrdersVisibleWhenInactive FROM dbo.Orders;
REVERT;
-- restore the original attributes
UPDATE dbo.Staff SET Region = N'Addis Ababa', IsActive = 1 WHERE DbUserName = N'sales_addis';
PRINT 'Attributes restored (Addis Ababa, active).';
GO
