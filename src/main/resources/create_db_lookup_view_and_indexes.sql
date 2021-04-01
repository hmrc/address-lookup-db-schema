CREATE OR REPLACE PROCEDURE create_address_lookup_view(the_schema_name varchar)
    LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN
    EXECUTE format('SET search_path = %s', the_schema_name);

    UPDATE public.address_lookup_status
    SET status    = 'creating_view',
        timestamp = now()
    WHERE schema_name = the_schema_name;

    DROP MATERIALIZED VIEW IF EXISTS address_lookup;

    CREATE MATERIALIZED VIEW address_lookup AS
    SELECT b.uprn                                                                                              AS uprn,
           array_to_string(ARRAY [btrim(d.sub_building_name::text), btrim(d.building_name::text)], ', '::text) AS line1,
           array_to_string(
                   ARRAY [btrim(''::text || d.building_number), btrim(d.dependent_thoroughfare::text), btrim(d.thoroughfare::text)],
                   ' '::text)                                                                                  AS line2,
           array_to_string(ARRAY [btrim(d.double_dependent_locality::text), btrim(d.dependent_locality::text)],
                           ' '::text)                                                                          AS line3,
           CASE
               WHEN b.country::text = 'S'::text THEN 'GB-SCT'::text
               WHEN b.country::text = 'E'::text THEN 'GB-ENG'::text
               WHEN b.country::text = 'W'::text THEN 'GB-WLS'::text
               WHEN b.country::text = 'N'::text THEN 'GB-NIR'::text
               ELSE NULL::text
               END                                                                                             AS subdivision,
           CASE
               WHEN b.country::text = 'S'::text THEN 'UK'::text
               WHEN b.country::text = 'E'::text THEN 'UK'::text
               WHEN b.country::text = 'W'::text THEN 'UK'::text
               WHEN b.country::text = 'N'::text THEN 'UK'::text
               WHEN b.country::text = 'L'::text AND "substring"(d.postcode::text, 1, 1) = 'G'::text THEN 'GG'::text
               WHEN b.country::text = 'L'::text AND "substring"(d.postcode::text, 1, 1) = 'J'::text THEN 'JE'::text
               WHEN b.country::text = 'M'::text THEN 'IM'::text
               ELSE 'NOT_FOUND'::text
               END                                                                                             AS countrycode,
           b.local_custodian_code                                                                              AS localcustodiancode,
           CASE
               WHEN lower(l.language::text) = 'eng'::text THEN 'en'::text
               WHEN lower(l.language::text) = 'cym'::text THEN 'cy'::text
               ELSE NULL::text
               END                                                                                             AS language,
           b.blpu_state                                                                                        AS blpustate,
           b.logical_status                                                                                    AS logicalstatus,
           d.post_town                                                                                         AS posttown,
           upper(
                   regexp_replace(d.postcode::text, '[ \\t]+'::text, ' '::text))                               AS postcode,
           concat(b.latitude, ',', b.longitude)                                                                AS location,
           d.po_box_number                                                                                     AS poboxnumber,
           asd.administrative_area                                                                             AS localAuthority,
           to_tsvector('english'::regconfig, array_to_string(
                   ARRAY [
                       btrim(d.sub_building_name::text),
                       btrim(d.building_name::text),
                       btrim(d.building_number::text),
                       btrim(d.dependent_thoroughfare::text),
                       btrim(d.thoroughfare::text),
                       btrim(d.post_town::text),
                       btrim(d.double_dependent_locality::text),
                       btrim(d.dependent_locality::text),
                       btrim(asd.administrative_area::text),
                       btrim(d.po_box_number::text)],
                   ' '::text))                                                                                 AS address_lookup_ft_col
    FROM abp_delivery_point d
             JOIN abp_blpu b ON b.uprn = d.uprn
             JOIN abp_lpi l ON l.uprn = b.uprn
             JOIN abp_street_descriptor asd ON l.usrn = asd.usrn;

    UPDATE public.address_lookup_status
    SET status    = 'view_created',
        timestamp = now()
    WHERE schema_name = the_schema_name;

    CREATE INDEX IF NOT EXISTS address_lookup_ft_col_idx
        ON address_lookup USING gin (address_lookup_ft_col);

    UPDATE public.address_lookup_status
    SET status    = 'gin_index_created',
        timestamp = now()
    WHERE schema_name = the_schema_name;


    CREATE INDEX IF NOT EXISTS address_lookup_postcode_idx
        ON address_lookup (postcode);

    UPDATE public.address_lookup_status
    SET status    = 'postcode_index_created',
        timestamp = now()
    WHERE schema_name = the_schema_name;

    CREATE INDEX IF NOT EXISTS address_lookup_uprn_idx
        ON address_lookup (uprn);

    UPDATE public.address_lookup_status
    SET status    = 'uprn_index_created',
        timestamp = now()
    WHERE schema_name = the_schema_name;

    UPDATE public.address_lookup_status
    SET status    = 'public_view_created',
        timestamp = now()
    WHERE schema_name = the_schema_name;

    UPDATE public.address_lookup_status
    SET status    = 'completed',
        timestamp = now()
    WHERE schema_name = the_schema_name;
EXCEPTION
    WHEN OTHERS THEN
        UPDATE public.address_lookup_status
        SET status    = 'errored',
            error_message = SQLERRM,
            timestamp = now()
        WHERE schema_name = the_schema_name;
END;
$$
