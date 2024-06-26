/*
 * installers/mssql/install.sql
 * 
 * Transact-SQL flavored installer for the Packify package manager. For a typical SQL Server
 * instance, you should run this file as is.
 * 
 * Authors: Will Hinson
 * Created: 2024-06-22
 * Updated: 2024-06-25
 *
 */

----------------------------------------------------------------------------------------------------

/* Configuration variables for installation - don't change unless you know what you're doing */
DECLARE
    @DatabaseName           NVARCHAR(200)   = 'Packify',
    @PackageRepo            NVARCHAR(200)   = 'packify-sql/packages',
    @InstallBranch          NVARCHAR(200)   = 'wip/packify-bootstrap',

    @RawContentURLFormat    NVARCHAR(200)   = 'https://raw.githubusercontent.com/:repo/:branch/:packageDir',
    @RepoListingURLFormat   NVARCHAR(200)   = 'https://api.github.com/repos/:repo/git/trees/:branch?recursive=1',
    @PackagesDirectory      NVARCHAR(200)   = 'packify-packages',

    @TargetDialect          NVARCHAR(200)   = 'mssql',
    @TargetPlatform         NVARCHAR(200)   = 'windows',
    @TargetPackage          NVARCHAR(200)   = 'packify';

/* Construct the required URLs for installation */
DECLARE
    @RepositoryJsonURL      NVARCHAR(2000)  = CONCAT(
        REPLACE(
            REPLACE(
                REPLACE(
                    @RawContentURLFormat,
                    ':repo',
                    @PackageRepo
                ),
                ':branch',
                @InstallBranch
            ),
            ':packageDir',
            @PackagesDirectory
        ),
        '/repository.json'
    ),
    @RepositoryListingURL   NVARCHAR(2000) = REPLACE(
        REPLACE(
            @RepoListingURLFormat,
            ':repo',
            @PackageRepo
        ),
        ':branch',
        @InstallBranch
    );

----------------------------------------------------------------------------------------------------

SET NOCOUNT ON;

PRINT CONCAT('Installing from ''', @PackageRepo, '''');
PRINT CONCAT('Fetching repository definition from ''', @PackageRepo, '''');

DECLARE
    @objHandle      INT,
    @hResult        INT,
    
    @errorNumber    INT,
    @errorMessage   NVARCHAR(400);

/* Dynamic query for issuing HTTP GET requests */
DECLARE @queryHttpGet NVARCHAR(MAX) = '
    DECLARE @targetUrl NVARCHAR(MAX) = '':targetUrl'';
    DECLARE
        @hresult        INT,
        @responseText   NVARCHAR(MAX),
        @statusCode     INT,
        @xmlHttpObject  INT,
        
        @errorNumber    INT,
        @errorMessage   NVARCHAR(MAX);

    PRINT CONCAT(''HTTP GET '', @targetUrl);

    /* Instantiate a new request object */
    EXEC @hresult = sp_OACreate
        ''MSXML2.ServerXMLHTTP'',
        @xmlHttpObject OUTPUT;
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99900;
        SET @errorMessage = CONCAT(
            ''Unable to create MSXML.ServerXMLHTTP object: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END

    /* Construct/send an HTTP GET request */
    EXEC @hresult = sp_OAMethod
        @xmlHttpObject,
        ''open'',
        NULL,
        ''GET'',
        @targetUrl,
        false;
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99910;
        SET @errorMessage = CONCAT(
            ''Unable to open request: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END

    /* Set headers for the request */
    EXEC @hresult = sp_OAMethod
        @xmlHttpObject,
        ''setRequestHeader'',
        NULL,
        ''Cache-Control'',
        ''no-cache'';
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99920;
        SET @errorMessage = CONCAT(
            ''Unable to set Cache-Control header for request: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END

    EXEC @hresult = sp_OAMethod
        @xmlHttpObject,
        ''setRequestHeader'',
        NULL,
        ''Pragma'',
        ''no-cache'';
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99930;
        SET @errorMessage = CONCAT(
            ''Unable to set Pragma header for request: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END

    EXEC @hresult = sp_OAMethod
        @xmlHttpObject,
        ''setRequestHeader'',
        NULL,
        ''User-Agent'',
        ''packify-install/0.2.0'';
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99940;
        SET @errorMessage = CONCAT(
            ''Unable to set User-Agent header for request: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END

    EXEC @hresult = sp_OAMethod
        @xmlHttpObject,
        ''send'',
        NULL,
        '''';
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99950;
        SET @errorMessage = CONCAT(
            ''Unable to send request: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            ),
            IIF(
                @hresult = 0x80072EE7,
                CONCAT(
                    '' (It is likely your database server cannot '',
                    ''connect to the remote server. Check your '',
                    ''server''''s Internet connection.)''
                ),
                ''''
            )
        );

        GOTO RequestError;
    END

    /* Get the status code and check for success */
    EXEC @hresult = sp_OAGetProperty
        @xmlHttpObject,
        ''status'',
        @statusCode OUT;
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99960;
        SET @errorMessage = CONCAT(
            ''Unable to get response status code: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END
    IF @statusCode NOT BETWEEN 200 AND 299 BEGIN
        SET @errorNumber = 99970;
        SET @errorMessage = CONCAT(
            ''Server responded with error status code '',
            @statusCode
        );

        GOTO RequestError;
    END

    /* Get the content of the response */
    DECLARE @tblResult TABLE (
        [ResultField]   NVARCHAR(MAX)
    );
    INSERT INTO
        @tblResult
    EXEC @hresult = sp_OAGetProperty
        @xmlHttpObject,
        ''responseText'';

    IF @hresult != 0 BEGIN
        SET @errorNumber = 99980;
        SET @errorMessage = CONCAT(
            ''Unable to get response: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END

    /* Free the request object */
    EXEC @hresult = sp_OADestroy
        @xmlHttpObject;
    IF @hresult != 0 BEGIN
        SET @errorNumber = 99990;
        SET @errorMessage = CONCAT(
            ''Unable to destroy MSXML.ServerXMLHTTP object: Error '',
            CONVERT(
                NVARCHAR(MAX),
                CAST(@hresult AS VARBINARY(8)),
                1
            )
        );

        GOTO RequestError;
    END

    SELECT
        @responseOut = [ResultField]
    FROM
        @tblResult;
    
    RETURN;
    
RequestError:
    IF @xmlHttpObject IS NOT NULL BEGIN
        EXEC @hresult = sp_OADestroy @xmlHttpObject;
    END;

    THROW
        @errorNumber,
        @errorMessage,
        1;
';

/* issue an HTTP GET request for the repository.json file */
DECLARE @dynamicQuery NVARCHAR(MAX) = REPLACE(
    @queryHttpGet,
    ':targetUrl',
    REPLACE(@RepositoryJsonURL, '''', '''''')
);
DECLARE @repositoryJson NVARCHAR(MAX);
EXEC sp_executesql
    @dynamicQuery,
    N'@responseOut NVARCHAR(MAX) OUTPUT',
    @responseOut = @repositoryJson OUTPUT;

/* Parse out the repository version and name */
DECLARE
    @repositoryVersion  NVARCHAR(200),
    @repositoryName     NVARCHAR(4000);

BEGIN TRY
    SELECT
        @repositoryVersion = [repositoryVersion],
        @repositoryName = [name]
    FROM (
        SELECT
            [key],
            [value]
        FROM
            OPENJSON(@repositoryJson)
    ) AS a
    PIVOT (
        MAX([value])
        FOR
            [key]
        IN (
            [repositoryVersion],
            [name]
        )
    ) AS _;
END TRY
BEGIN CATCH
    SET @errorNumber = 99000;
    SET @errorMessage = CONCAT(
        'Unable to parse out repository name and version: ',
        ERROR_MESSAGE(),
        ' (', ERROR_NUMBER(), ')'
    );

    GOTO Error;
END CATCH

PRINT CONCAT(
    'Installing from ''',
    @repositoryName,
    ''''
);
PRINT 'Fetching package list from repository';

/* Get a list of packages in the repository */
SET @dynamicQuery = REPLACE(
    @queryHttpGet,
    ':targetUrl',
    REPLACE(@RepositoryListingURL, '''', '''''')
);
DECLARE @repositoryListingJson NVARCHAR(MAX);
EXEC sp_executesql
    @dynamicQuery,
    N'@responseOut NVARCHAR(MAX) OUTPUT',
    @responseOut = @repositoryListingJson OUTPUT;

DECLARE @tblDirectoryListing TABLE (
    [ObjectID]      INT PRIMARY KEY,
    [Path]          NVARCHAR(4000) NOT NULL,
    [Type]          NVARCHAR(200) NOT NULL
);
DECLARE @tblPackages TABLE (
    [PackageName]   NVARCHAR(400) PRIMARY KEY
);

BEGIN TRY
    INSERT INTO
        @tblDirectoryListing
    SELECT
        [ObjectID],
        [Path],
        [Type]
    FROM (
        SELECT
            ObjectID = a.[key],
            b.[key],
            b.[value]
        FROM
            OPENJSON(
                @repositoryListingJson,
                '$.tree'
            ) AS a
        CROSS APPLY OPENJSON(
            [value]
        ) AS b
    ) AS a
    PIVOT (
        MAX([value])
        FOR
            [key]
        IN (
            [path],
            [mode],
            [type],
            [sha],
            [size],
            [url]
        )
    ) AS b;

    INSERT INTO
        @tblPackages
    SELECT
        PackageName = REVERSE(
            LEFT(
                REVERSE([Path]),
                CHARINDEX('/', REVERSE([Path])) - 1
            )
        )
    FROM
        @tblDirectoryListing
    WHERE
        /* The object should be a directory but not the packages directory itself. Additionally,
            it should be a top-level directory in the packages directory */
        [Type] = 'tree'
        AND [Path] != @PackagesDirectory
        AND [Path] LIKE CONCAT(@PackagesDirectory, '/%')
        AND [Path] NOT LIKE CONCAT(@PackagesDirectory, '/%/%');
END TRY
BEGIN CATCH
    SET @errorNumber = 99010;
    SET @errorMessage = CONCAT(
        'Unable to fetch list of packages from repository: ',
        ERROR_MESSAGE(),
        ' (', ERROR_NUMBER(), ')'
    );

    GOTO Error;
END CATCH

DECLARE @packageCount INT = (
    SELECT
        COUNT(*)
    FROM
        @tblPackages
);
PRINT CONCAT(
    'Found ', FORMAT(@packageCount, '#,##'), ' package',
    IIF(@packageCount != 1, 's', ''), ' in repository'
);

/* Check if the target package is in the repository */
IF NOT EXISTS (
    SELECT
        *
    FROM
        @tblPackages
    WHERE
        [PackageName] = @TargetPackage
) BEGIN
    SET @errorNumber = 99020;
    SET @errorMessage = CONCAT(
        'Target package ''', @TargetPackage, ''' not found in repository'
    );

    GOTO Error;
END

/* Get the most recent version available. We have to parse out the version strings */
DECLARE @packagePath NVARCHAR(2000) = CONCAT(
    @PackagesDirectory,
    '/',
    @TargetPackage
);
DECLARE @tblPackageVersions TABLE (
    [Version]               NVARCHAR(200) PRIMARY KEY,
    [Major]                 INT,
    [Minor]                 INT,
    [Patch]                 INT,
    [PackageVersionPrefix]  NVARCHAR(2000) NOT NULL,
    [PackageJsonPath]       NVARCHAR(2000) NOT NULL
);

INSERT INTO
    @tblPackageVersions
SELECT DISTINCT
    *
FROM (
    SELECT
        *,
        Major = CONVERT(
            INT,
            LEFT(
                [Version],
                CHARINDEX('.', [Version]) - 1
            )
        ),
        Minor = CONVERT(
            INT,
            SUBSTRING(
                [Version], 
                CHARINDEX('.', [Version]) + 1, 
                CHARINDEX(
                    '.', [Version] + '.',
                    CHARINDEX('.', [Version]) + 1
                )
                - CHARINDEX('.', [Version]) - 1
        )),
        Patch = CONVERT(
            INT,
            SUBSTRING(
                [Version], 
                CHARINDEX(
                    '.',
                    [Version] + '.',
                    CHARINDEX('.', [Version]) + 1
                )
                + 1, 
                LEN(Version)
            )
        ),
        PackageVersionPrefix = CONCAT(
            @packagePath,
            '/',
            [Version]
        ),
        PackageJsonPath = CONCAT(
            @packagePath,
            '/',
            [Version],
            '/',
            @TargetDialect,
            '/',
            @TargetPlatform,
            '/package.json'
        )
    FROM (
        SELECT
            [Version] = LEFT(
                RIGHT(
                    [Path],
                    LEN([Path]) - LEN(@packagePath) - 1
                ),
                CHARINDEX(
                    '/',
                    RIGHT(
                        [Path],
                        LEN([Path]) - LEN(@packagePath) - 1
                    )
                ) - 1
            )
        FROM
            @tblDirectoryListing
        WHERE
            [Path] LIKE CONCAT(
                @packagePath,
                '/%/',
                @TargetDialect,
                '/',
                @TargetPlatform,
                '/%'
            )
            AND [Path] NOT LIKE CONCAT(
                @packagePath,
                '/%/',
                @TargetDialect,
                '/',
                @TargetPlatform,
                '/%/%'
            )
    ) AS _
) AS _
WHERE
    [PackageJsonPath] IN (
        SELECT
            [Path]
        FROM
            @tblDirectoryListing
    );

/* Check if the target package has a version available in the repository */
IF NOT EXISTS (
    SELECT
        *
    FROM
        @tblPackageVersions
) BEGIN
    SET @errorNumber = 99030;
    SET @errorMessage = CONCAT(
        'No version for target package ''', @TargetPackage, ''' found in repository'
    );

    GOTO Error;
END

DECLARE
    @targetVersion      NVARCHAR(2000),
    @packagePrefix      NVARCHAR(2000);
SELECT TOP 1
    @targetVersion = [Version],
    @packagePrefix = [PackageVersionPrefix]
FROM
    @tblPackageVersions;

PRINT CONCAT(
    'Installing ', @TargetPackage, ' ', @targetVersion,
    ' from directory ', @packagePrefix
);
PRINT 'Fetching package.json';

/* Read the JSON for this package */
SET @dynamicQuery = REPLACE(
    @queryHttpGet,
    ':targetUrl',
    CONCAT(
        REPLACE(
            REPLACE(
                REPLACE(
                    @RawContentURLFormat,
                    ':repo',
                    @PackageRepo
                ),
                ':branch',
                @InstallBranch
            ),
            ':packageDir',
            ''
        ),
        @packagePrefix,
        '/',
        @TargetDialect,
        '/',
        @TargetPlatform,
        '/package.json'
    )
);
DECLARE @packageJson NVARCHAR(MAX);
EXEC sp_executesql
    @dynamicQuery,
    N'@responseOut NVARCHAR(MAX) OUTPUT',
    @responseOut = @packageJson OUTPUT;

/* Get a list of required install files */
DECLARE @tblInstallFiles TABLE (
    [OrdinalPosition]   INT NOT NULL,
    [FilePath]          NVARCHAR(2000) NOT NULL
);

BEGIN TRY
    INSERT INTO
        @tblInstallFiles
    SELECT
        OrdinalPosition = [key],
        FilePath = [value]
    FROM
        OPENJSON(
            @packageJson,
            '$.files.install'
        );
END TRY
BEGIN CATCH
    SET @errorNumber = 99040;
    SET @errorMessage = CONCAT(
        'Failed getting list of install scripts: ',
        ERROR_MESSAGE(),
        ' (', ERROR_NUMBER(), ')'
    );

    GOTO Error;
END CATCH

DECLARE @installFileCount INT = (
    SELECT
        COUNT(*)
    FROM
        @tblInstallFiles
);
PRINT CONCAT(
    'Found ',
    @installFileCount,
    ' install script',
    IIF(
        @installFileCount != 1,
        's',
        ''
    ),
    ' for ',
    @TargetPackage,
    ' ',
    @targetVersion
);

/* Get the value for the database parameter */
DECLARE
    @databaseParamMethod            NVARCHAR(200),
    @databaseParamEscapedValue      NVARCHAR(200),
    @databaseParamUnescapedValue    NVARCHAR(200);
SELECT
    @databaseParamMethod = [method],
    @databaseParamEscapedValue = [escapedValue],
    @databaseParamUnescapedValue = [unescapedValue]
FROM (
    SELECT
        FieldName = [key],
        FieldValue = [value]
    FROM
        OPENJSON(
            @packageJson,
            '$.parameters.targets.database'
        )
) AS _
PIVOT (
    MAX([FieldValue])
    FOR
        [FieldName]
    IN (
        [method],
        [escapedValue],
        [unescapedValue]
    )
) AS _;

/* Cursor over all of the installation scripts and run each of them */
DECLARE installFileCursor CURSOR FOR
SELECT
    [OrdinalPosition],
    [FilePath]
FROM
    @tblInstallFiles;

DECLARE
    @ordinalPosition    INT,
    @filePath           NVARCHAR(2000);

OPEN installFileCursor;

FETCH NEXT FROM
    installFileCursor
INTO
    @ordinalPosition,
    @filePath;

WHILE @@FETCH_STATUS = 0 BEGIN
    /* Issue a GET request for this install file and retrieve its source */
    PRINT CONCAT('Fetching install file ', @filePath);
    SET @dynamicQuery = REPLACE(
        @queryHttpGet,
        ':targetUrl',
        CONCAT(
            REPLACE(
                REPLACE(
                    REPLACE(
                        @RawContentURLFormat,
                        ':repo',
                        @PackageRepo
                    ),
                    ':branch',
                    @InstallBranch
                ),
                ':packageDir',
                ''
            ),
            @packagePrefix,
            '/',
            @TargetDialect,
            '/',
            @TargetPlatform,
            '/',
            @filePath
        )
    );
    DECLARE @installFileSource NVARCHAR(MAX);
    EXEC sp_executesql
        @dynamicQuery,
        N'@responseOut NVARCHAR(MAX) OUTPUT',
        @responseOut = @installFileSource OUTPUT;
    
    /* Perform substitution for the database name */
    SET @installFileSource = REPLACE(
        @installFileSource,
        @databaseParamUnescapedValue,
        @DatabaseName
    );
    SET @installFileSource = REPLACE(
        @installFileSource,
        @databaseParamEscapedValue,
        CONCAT('[', REPLACE(@DatabaseName, ']', ']]'), ']')
    );
    
    /* Execute the remote source of the install file */
    PRINT CONCAT('Executing install file ', @filePath);
    PRINT REPLICATE('-', 100);
    
    EXEC sp_executesql
        @installFileSource;
    
    PRINT REPLICATE('-', 100);

    FETCH NEXT FROM
        installFileCursor
    INTO
        @ordinalPosition,
        @filePath;
END

CLOSE installFileCursor;
DEALLOCATE installFileCursor;

PRINT CONCAT(
    'Installation complete! ',
    @TargetPackage, ' ', @targetVersion,
    ' was installed.'
);

RETURN;

Error:
    THROW
        @errorNumber,
        @errorMessage,
        1;
