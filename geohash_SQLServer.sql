DROP FUNCTION IF EXISTS dbo.geohash_encode;
go
CREATE FUNCTION dbo.geohash_encode (
    @_latitude float,
    @_longitude float,
    @_precision TINYINT
)
RETURNS VARCHAR(12)
-- 'geohash_encode(57.64911, 10.40744, 12) => u4pruydqquvx'
BEGIN
    DECLARE @latL float = -90.0;
    DECLARE @latR float = 90.0;

    DECLARE @lonT float = -180.0;
    DECLARE @lonB float = 180.0;

    DECLARE @bit TINYINT = 0;
    DECLARE @bit_pos TINYINT = 0;
    DECLARE @ch CHAR(1) = '';
    DECLARE @ch_pos INT = 0;
    DECLARE @mid float = NULL;

    DECLARE @even BIT = 1;
    DECLARE @geohash VARCHAR(12) = '';
    DECLARE @geohash_length TINYINT = 0;

    /*
    CREATE TEMPORARY TABLE `TMP_BIT` (`pos` TINYINT UNSIGNED, `val` TINYINT UNSIGNED) ENGINE=MEMORY;
    CREATE TEMPORARY TABLE `TMP_BASE32` (`pos` TINYINT UNSIGNED, `val` CHAR(1)) ENGINE=MEMORY;
    INSERT INTO `TMP_BIT` (`pos`, `val`) VALUES (0, 16), (1, 8), (2, 4), (3, 2), (4, 1);
    INSERT INTO `TMP_BASE32` (`pos`, `val`) VALUES
        (0, '0'), (1, '1'), (2, '2'), (3, '3'), (4, '4'),
        (5, '5'), (6, '6'), (7, '7'), (8, '8'), (9, '9'),
        (10, 'b'), (11, 'c'), (12, 'd'), (13, 'e'), (14, 'f'),
        (15, 'g'), (16, 'h'), (17, 'j'), (18, 'k'), (19, 'm'),
        (20, 'n'), (21, 'p'), (22, 'q'), (23, 'r'), (24, 's'),
        (25, 't'), (26, 'u'), (27, 'v'), (28, 'w'), (29, 'x'),
        (30, 'y'), (31, 'z');
    */

    IF @_precision IS NULL
        SET @_precision = 12;

    WHILE @geohash_length < @_precision
	BEGIN
        IF @even = 1
		BEGIN
            --
            -- is even
            --
            
            SET @mid = (@lonT + @lonB) / 2;
            IF @mid < @_longitude
			BEGIN
                SET @bit = dbo.geohash_bit(@bit_pos);
                /*
                 * SELECT `val` INTO bit FROM `TMP_BIT` WHERE `pos` = bit_pos;
                 */
                SET @ch_pos = @ch_pos | @bit;
                SET @lonT = @mid;
			END
            ELSE
                SET @lonB = @mid;
		END
        ELSE
		BEGIN
            --
            -- not even
            --
            
            SET @mid = (@latL + @latR) / 2;
            IF @mid < @_latitude
			BEGIN
                SET @bit = dbo.geohash_bit(@bit_pos);
                /*
                 * SELECT `val` INTO bit FROM `TMP_BIT` WHERE `pos` = bit_pos;
                 */
                SET @ch_pos = @ch_pos | @bit;
                SET @latL = @mid;
			END
            ELSE
                SET @latR = @mid;
        END

        -- toggle even
        SET @even = ~@even;

        IF @bit_pos < 4
            SET @bit_pos = @bit_pos + 1;
        ELSE
		BEGIN
            SET @ch = dbo.geohash_base32(@ch_pos);
            /*
             * SELECT `val` INTO ch FROM `TMP_BASE32` WHERE `pos` = ch_pos;
             */
            SET @geohash = CONCAT(@geohash, @ch);
            SET @bit_pos = 0;
            SET @ch_pos = 0;
        END

        SET @geohash_length = LEN(@geohash);
    END

    /*
    DROP TEMPORARY TABLE IF EXISTS `TMP_BIT`;
    DROP TEMPORARY TABLE IF EXISTS `TMP_BASE32`;
    */

    RETURN @geohash;
END
go

DROP FUNCTION IF EXISTS dbo.geohash_decode;
go
CREATE FUNCTION dbo.geohash_decode (
    @_geohash VARCHAR(12)
)
RETURNS CHAR(77)
-- 'geohash_decode(u4pru) => csv'
BEGIN
    DECLARE @latL float = -90.0;
    DECLARE @latR float = 90.0;

    DECLARE @lonT float = -180.0;
    DECLARE @lonB float = 180.0;

    DECLARE @lat_err float = 90.0;
    DECLARE @lon_err float = 180.0;

    DECLARE @ch CHAR(1) = '';
    DECLARE @ch_pos INT = 0;

    DECLARE @even BIT  = 1;
    DECLARE @geohash_length INT = 0;
    DECLARE @geohash_pos TINYINT  = 0;
    DECLARE @pos TINYINT  = 0;

    DECLARE @mask TINYINT  = 0;
    DECLARE @masked_val TINYINT  = 0;

    DECLARE @buf VARCHAR(77) = '';

    SET @geohash_length = LEN(@_geohash);

    WHILE @geohash_pos < @geohash_length 
	BEGIN
        SELECT @ch = dbo.geohash_base32(@geohash_pos);
        SELECT @ch_pos = dbo.geohash_base32_index(@ch);

        SET @pos = 0;
        WHILE @pos < 5 
		BEGIN
            SELECT @mask = dbo.geohash_bit(@pos);
            SET @masked_val = @ch_pos & @mask;

            IF @even = 1
			BEGIN
                SET @lon_err = @lon_err / 2;

                IF @masked_val != 0
                    SET @lonT = (@lonT + @lonB) / 2;
                ELSE
                    SET @lonB = (@lonT + @lonB) / 2;
			END
            ELSE
			BEGIN
                SET @lat_err = @lat_err / 2;

                IF @masked_val != 0
                    SET @latL = (@latL + @latR) / 2;
                ELSE
                    SET @latR = (@latL + @latR) / 2;
            END
			            
            SET @even = ~@even;
            SET @pos = @pos + 1;
        END

        SET @geohash_pos = @geohash_pos + 1;
    END --while

    SET @lat_err = (@latL + @latR) / 2;
    SET @lon_err = (@lonT + @lonB) / 2;

    /*
    IF _column_output = 1 THEN
        SELECT latL AS 'latitude', lonT AS 'longitude'
        UNION ALL
        SELECT latR AS 'latitude', lonB AS 'longitude'
        UNION ALL
        SELECT lat_err AS 'latitude', lon_err AS 'longitude';
    END IF;
    */

    SET @buf = CONCAT(@buf, @latL, ',', @lonT);
    SET @buf = CONCAT(@buf, '\n');
    SET @buf = CONCAT(@buf, @latR, ',', @lonB);
    SET @buf = CONCAT(@buf, '\n');
    SET @buf = CONCAT(@buf, @lat_err, ',', @lon_err);

    RETURN @buf;
END

go
DROP FUNCTION IF EXISTS dbo.geohash_bit;
go
CREATE FUNCTION dbo.geohash_bit (
    @_bit TINYINT
)
RETURNS TINYINT 
-- 'geohash_bit(0) => 16, geohash_bit(1) => 8'
BEGIN
    DECLARE @bit TINYINT =

    CASE @_bit
        WHEN 0 THEN 16
        WHEN 1 THEN 8
        WHEN 2 THEN 4
        WHEN 3 THEN 2
        WHEN 4 THEN 1
		ELSE NULL
    END;

    RETURN @bit;
END

go
DROP FUNCTION IF EXISTS dbo.geohash_base32;
go
CREATE FUNCTION dbo.geohash_base32 (
    @_index TINYINT
)
RETURNS CHAR(1)
-- 'geohash_base32(0) => "0", geohash_base32(31) => "z"'
BEGIN
    DECLARE @ch CHAR(1) =

    CASE @_index
        WHEN 0 THEN '0'
        WHEN 1 THEN '1'
        WHEN 2 THEN '2'
        WHEN 3 THEN '3'
        WHEN 4 THEN '4'
        WHEN 5 THEN '5'
        WHEN 6 THEN '6'
        WHEN 7 THEN '7'
        WHEN 8 THEN '8'
        WHEN 9 THEN '9'
        WHEN 10 THEN 'b'
        WHEN 11 THEN 'c'
        WHEN 12 THEN 'd'
        WHEN 13 THEN 'e'
        WHEN 14 THEN 'f'
        WHEN 15 THEN 'g'
        WHEN 16 THEN 'h'
        WHEN 17 THEN 'j'
        WHEN 18 THEN 'k'
        WHEN 19 THEN 'm'
        WHEN 20 THEN 'n'
        WHEN 21 THEN 'p'
        WHEN 22 THEN 'q'
        WHEN 23 THEN 'r'
        WHEN 24 THEN 's'
        WHEN 25 THEN 't'
        WHEN 26 THEN 'u'
        WHEN 27 THEN 'v'
        WHEN 28 THEN 'w'
        WHEN 29 THEN 'x'
        WHEN 30 THEN 'y'
        WHEN 31 THEN 'z'
		ELSE NULL
    END;

    RETURN @ch;
END
go

DROP FUNCTION IF EXISTS dbo.geohash_base32_index;
go
CREATE FUNCTION dbo.geohash_base32_index (
    @ch CHAR(1)
)
RETURNS TINYINT
-- 'geohash_base32_index("b") => 10, geohash_base32_index("z") => 31'
BEGIN
    DECLARE @idx TINYINT = 

    CASE @ch
        WHEN '0' THEN 0
        WHEN '1' THEN 1
        WHEN '2' THEN 2
        WHEN '3' THEN 3
        WHEN '4' THEN 4
        WHEN '5' THEN 5
        WHEN '6' THEN 6
        WHEN '7' THEN 7
        WHEN '8' THEN 8
        WHEN '9' THEN 9
        WHEN 'b' THEN 10
        WHEN 'c' THEN 11
        WHEN 'd' THEN 12
        WHEN 'e' THEN 13
        WHEN 'f' THEN 14
        WHEN 'g' THEN 15
        WHEN 'h' THEN 16
        WHEN 'j' THEN 17
        WHEN 'k' THEN 18
        WHEN 'm' THEN 19
        WHEN 'n' THEN 20
        WHEN 'p' THEN 21
        WHEN 'q' THEN 22
        WHEN 'r' THEN 23
        WHEN 's' THEN 24
        WHEN 't' THEN 25
        WHEN 'u' THEN 26
        WHEN 'v' THEN 27
        WHEN 'w' THEN 28
        WHEN 'x' THEN 29
        WHEN 'y' THEN 30
        WHEN 'z' THEN 31
		ELSE NULL
    END;
    RETURN @idx;
END
