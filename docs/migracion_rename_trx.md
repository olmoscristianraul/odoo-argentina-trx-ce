# Migración: renombrado de módulos `l10n_ar_edi*` → `l10n_ar_trx_*`

**Aplica sólo a bases que ya tenían instalados los nombres anteriores.**
Una instalación nueva no necesita nada de esto.

| Nombre anterior | Nombre nuevo | Versión nueva |
|---|---|---|
| `l10n_ar_edi` | `l10n_ar_trx_edi` | 19.0.0.8.0 |
| `l10n_ar_edi_base` | `l10n_ar_trx_edi_base` | 19.0.0.4.0 |
| `l10n_ar_pos_edi` | `l10n_ar_trx_pos_edi` | 19.0.0.2.0 |

Los demás módulos del paquete conservan su nombre; sólo cambian su
`depends` (y suben una versión de parche).

## Por qué hace falta un paso manual

Odoo identifica un módulo instalado por su nombre técnico. Si el
directorio `l10n_ar_edi` desaparece del addons path y aparece
`l10n_ar_trx_edi`, Odoo arranca con `l10n_ar_edi` "instalado pero
inexistente": los campos, vistas y crones del módulo quedan huérfanos y
la facturación deja de funcionar. Por eso la base se renombra **antes**
de arrancar con el código nuevo. Los datos (facturas, CAE, logs de WS,
configuración de certificados) no se tocan: sólo cambian las referencias
al nombre del módulo.

## Procedimiento

El orden importa. No saltear el backup: es el rollback.

1. **Backup** de la base y del filestore.
2. **Detener Odoo** (todos los workers y el cron que apunten a esa base).
3. Con el código **viejo** todavía en disco, ejecutar el script sobre la base:

   ```
   psql -U <usuario> -d <base> -v ON_ERROR_STOP=1 -f docs/rename_trx_modules.sql
   ```

   El script:
   - es idempotente (si ya está renombrado, no hace nada);
   - aborta si el `l10n_ar_edi` instalado no es de Trixocom (por ejemplo,
     el de Odoo Enterprise, que no debe tocarse);
   - termina con un `SELECT` de verificación que **debe devolver 0 filas**.

4. Reemplazar el código por la versión con los nombres nuevos
   (`git pull` del mirror; los directorios viejos ya no existen).
5. Arrancar Odoo actualizando el módulo base, que propaga a todos los
   dependientes:

   ```
   odoo -d <base> -u l10n_ar_trx_edi_base --stop-after-init
   ```

   y luego arrancar normalmente.

6. Verificar: Apps → los tres módulos figuran con el nombre nuevo y estado
   *Instalado*; abrir una factura con CAE y ver que el tab AFIP y el PDF
   con QR siguen intactos; en POS, emitir un ticket de prueba.

## Rollback

Restaurar el backup del paso 1 y volver al código anterior
(en el mirror, el commit anterior al renombrado: `c048333`). No hay migración inversa
automática.

## Qué toca el script

Las mismas tablas que `util.rename_module` de
[odoo/upgrade-util](https://github.com/odoo/upgrade-util/blob/master/src/util/modules.py):

- `ir_module_module.name`
- `ir_module_module_dependency.name`
- `ir_model_data.module` (todos los xmlids del módulo) y el xmlid
  `base.module_<nombre>` del propio módulo
- `ir_ui_view.key` (`<modulo>.<xmlid>` de las vistas)

Los assets del POS (`l10n_ar_trx_pos_edi/static/...`) se regeneran solos al
actualizar: se leen del manifest, no de la base.
