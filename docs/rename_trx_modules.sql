-- rename_trx_modules.sql — Trixocom
--
-- Renombra en una base Odoo 19 YA INSTALADA los módulos de Trixocom que
-- cambiaron de nombre técnico (sept. 2026), sin perder datos ni
-- configuración:
--
--     l10n_ar_edi       -> l10n_ar_trx_edi
--     l10n_ar_edi_base  -> l10n_ar_trx_edi_base
--     l10n_ar_pos_edi   -> l10n_ar_trx_pos_edi
--
-- Cubre las mismas tablas que `util.rename_module` de odoo/upgrade-util:
-- ir_module_module, ir_module_module_dependency, ir_model_data (registros
-- del módulo y el xmlid base.module_<nombre>) e ir_ui_view.key.
--
-- CÓMO USARLO (ver docs/migracion_rename_trx.md):
--   1. Backup de la base (y filestore).
--   2. Odoo DETENIDO (ningún worker corriendo contra esta base).
--   3. psql -d <base> -v ON_ERROR_STOP=1 -f rename_trx_modules.sql
--   4. Reemplazar el código por la versión con los nombres nuevos.
--   5. Arrancar Odoo con: -u l10n_ar_trx_edi_base  (propaga a dependientes).
--
-- Es idempotente: si los módulos ya están renombrados no hace nada.
-- Aborta si el `l10n_ar_edi` instalado NO es el de Trixocom (p. ej. el de
-- Odoo Enterprise), que no debe tocarse.

BEGIN;

DO $$
DECLARE
    pares  text[][] := ARRAY[
        ['l10n_ar_edi',      'l10n_ar_trx_edi'],
        ['l10n_ar_edi_base', 'l10n_ar_trx_edi_base'],
        ['l10n_ar_pos_edi',  'l10n_ar_trx_pos_edi']
    ];
    viejo  text;
    nuevo  text;
    autor  text;
    estado text;
    n      int;
BEGIN
    FOR i IN 1 .. array_length(pares, 1) LOOP
        viejo := pares[i][1];
        nuevo := pares[i][2];

        SELECT author, state INTO autor, estado
          FROM ir_module_module WHERE name = viejo;

        IF NOT FOUND THEN
            RAISE NOTICE '[%] no existe en ir_module_module: nada que hacer', viejo;
            CONTINUE;
        END IF;

        IF estado <> 'installed' THEN
            -- No instalado: basta con borrar la fila vieja; Odoo recrea la
            -- nueva al actualizar la lista de apps.
            DELETE FROM ir_module_module_dependency
             WHERE module_id = (SELECT id FROM ir_module_module WHERE name = viejo);
            DELETE FROM ir_model_data
             WHERE module = 'base' AND model = 'ir.module.module' AND name = 'module_' || viejo;
            DELETE FROM ir_module_module WHERE name = viejo;
            RAISE NOTICE '[%] estaba en estado % (no instalado): fila eliminada', viejo, estado;
            CONTINUE;
        END IF;

        IF coalesce(autor, '') NOT ILIKE '%trixocom%' THEN
            RAISE EXCEPTION '[%] está instalado pero su autor es "%", no Trixocom. '
                            'Puede ser el módulo de Odoo Enterprise: NO se renombra. Abortando.',
                            viejo, autor;
        END IF;

        -- Si alguien actualizó la lista de apps con el código nuevo ya en
        -- disco, existe una fila "uninstalled" con el nombre nuevo: se
        -- elimina para no violar el unique(name).
        IF EXISTS (SELECT 1 FROM ir_module_module WHERE name = nuevo) THEN
            IF EXISTS (SELECT 1 FROM ir_module_module WHERE name = nuevo AND state <> 'uninstalled') THEN
                RAISE EXCEPTION '[%] ya existe con estado distinto de uninstalled. Revisar a mano.', nuevo;
            END IF;
            DELETE FROM ir_module_module_dependency
             WHERE module_id = (SELECT id FROM ir_module_module WHERE name = nuevo);
            DELETE FROM ir_model_data
             WHERE module = 'base' AND model = 'ir.module.module' AND name = 'module_' || nuevo;
            DELETE FROM ir_module_module WHERE name = nuevo;
            RAISE NOTICE '[%] fila "uninstalled" previa eliminada', nuevo;
        END IF;

        UPDATE ir_module_module SET name = nuevo WHERE name = viejo;

        UPDATE ir_module_module_dependency SET name = nuevo WHERE name = viejo;
        GET DIAGNOSTICS n = ROW_COUNT;
        RAISE NOTICE '[% -> %] dependencias actualizadas: %', viejo, nuevo, n;

        UPDATE ir_model_data SET module = nuevo WHERE module = viejo;
        GET DIAGNOSTICS n = ROW_COUNT;
        RAISE NOTICE '[% -> %] ir_model_data actualizados: %', viejo, nuevo, n;

        UPDATE ir_model_data SET name = 'module_' || nuevo
         WHERE module = 'base' AND model = 'ir.module.module' AND name = 'module_' || viejo;

        UPDATE ir_ui_view
           SET key = nuevo || substr(key, length(viejo) + 1)
         WHERE key LIKE replace(viejo, '_', '\_') || '.%';
        GET DIAGNOSTICS n = ROW_COUNT;
        RAISE NOTICE '[% -> %] ir_ui_view.key actualizados: %', viejo, nuevo, n;
    END LOOP;
END $$;

-- Verificación: no debe quedar ninguna referencia a los nombres viejos.
SELECT 'ir_module_module' AS tabla, name AS ref FROM ir_module_module
 WHERE name IN ('l10n_ar_edi', 'l10n_ar_edi_base', 'l10n_ar_pos_edi')
UNION ALL
SELECT 'ir_module_module_dependency', name FROM ir_module_module_dependency
 WHERE name IN ('l10n_ar_edi', 'l10n_ar_edi_base', 'l10n_ar_pos_edi')
UNION ALL
SELECT 'ir_model_data', module || '.' || name FROM ir_model_data
 WHERE module IN ('l10n_ar_edi', 'l10n_ar_edi_base', 'l10n_ar_pos_edi')
UNION ALL
SELECT 'ir_ui_view', key FROM ir_ui_view
 WHERE key LIKE 'l10n\_ar\_edi.%' OR key LIKE 'l10n\_ar\_edi\_base.%' OR key LIKE 'l10n\_ar\_pos\_edi.%';

COMMIT;
