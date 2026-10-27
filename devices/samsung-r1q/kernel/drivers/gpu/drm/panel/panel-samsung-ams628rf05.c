// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung AMS628RF05 (S6E3FC2 DDIC) 1080x2400 command mode DSI panel,
 * as used in the Samsung Galaxy A80 (r1q).
 *
 * Init sequence and timings from the stock r1q device tree
 * (ss_dsi_panel_S6E3FC2_AMS670TA01_FHD); layout after
 * panel-samsung-ams581vf01.c.
 */

#include <linux/backlight.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>

#include <video/mipi_display.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>

/* Manufacturer Command Set */
#define MCS_PASSWD		0xf0
#define MCS_PASSWD2		0xfc

struct ams628rf05 {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset_gpio;
	struct gpio_desc *enable_gpio;
	struct regulator_bulk_data *supplies;
};

/*
 * ELVDD/ELVSS come from the PM6150L AMOLED block, which the bootloader
 * leaves on; only VDDIO is switched here.
 */
static const struct regulator_bulk_data ams628rf05_supplies[] = {
	{ .supply = "vddio" },
};

static inline struct ams628rf05 *to_ams628rf05(struct drm_panel *panel)
{
	return container_of(panel, struct ams628rf05, panel);
}

static void ams628rf05_reset(struct ams628rf05 *ctx)
{
	/* Stock reset sequence: low 10 ms, high 10 ms */
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
}

static int ams628rf05_on(struct ams628rf05 *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	/* Sleep Out */
	mipi_dsi_dcs_exit_sleep_mode_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 120);

	/* TE On */
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0x5a, 0x5a);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_TEAR_ON, 0x00);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0xa5, 0xa5);

	/* Column & Page Address: 0..1079, 0..2399 */
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_COLUMN_ADDRESS,
					 0x00, 0x00, 0x04, 0x37);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_PAGE_ADDRESS,
					 0x00, 0x00, 0x09, 0x5f);

	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0x5a, 0x5a);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD2, 0x5a, 0x5a);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xed, 0x00, 0x4c);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0xa5, 0xa5);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD2, 0xa5, 0xa5);

	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0x5a, 0x5a);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xeb, 0x1b, 0x41, 0xb0, 0x0e,
					 0x00, 0x1e, 0x5a, 0x1e, 0x1e);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0xa5, 0xa5);

	/* Brightness control on, ACL/gamma setup, full brightness */
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0x5a, 0x5a);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY, 0x20);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xb7, 0x00, 0x01, 0x53, 0x28,
				     0x4d, 0x00, 0x90, 0x04);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_DISPLAY_BRIGHTNESS,
					 0x03, 0xff);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0xa5, 0xa5);

	/* Display On (sent separately by the stock driver) */
	mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);

	return dsi_ctx.accum_err;
}

static void ams628rf05_off(struct ams628rf05 *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	mipi_dsi_dcs_set_display_off_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 20);
	mipi_dsi_dcs_enter_sleep_mode_multi(&dsi_ctx);

	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0x5a, 0x5a);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xb0, 0x05);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xf4, 0x01);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, MCS_PASSWD, 0xa5, 0xa5);
	mipi_dsi_msleep(&dsi_ctx, 120);
}

static int ams628rf05_prepare(struct drm_panel *panel)
{
	struct ams628rf05 *ctx = to_ams628rf05(panel);
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(ams628rf05_supplies), ctx->supplies);
	if (ret < 0)
		return ret;

	gpiod_set_value_cansleep(ctx->enable_gpio, 1);
	ams628rf05_reset(ctx);

	ret = ams628rf05_on(ctx);
	if (ret < 0) {
		gpiod_set_value_cansleep(ctx->reset_gpio, 1);
		gpiod_set_value_cansleep(ctx->enable_gpio, 0);
		regulator_bulk_disable(ARRAY_SIZE(ams628rf05_supplies), ctx->supplies);
		return ret;
	}

	return 0;
}

static int ams628rf05_unprepare(struct drm_panel *panel)
{
	struct ams628rf05 *ctx = to_ams628rf05(panel);

	ams628rf05_off(ctx);

	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	gpiod_set_value_cansleep(ctx->enable_gpio, 0);
	regulator_bulk_disable(ARRAY_SIZE(ams628rf05_supplies), ctx->supplies);

	return 0;
}

/* Stock: hfp 120, hsync 121, hbp 122; vfp 16, vsync 2, vbp 2; 60 Hz */
static const struct drm_display_mode ams628rf05_mode = {
	.clock = (1080 + 120 + 121 + 122) * (2400 + 16 + 2 + 2) * 60 / 1000,
	.hdisplay = 1080,
	.hsync_start = 1080 + 120,
	.hsync_end = 1080 + 120 + 121,
	.htotal = 1080 + 120 + 121 + 122,
	.vdisplay = 2400,
	.vsync_start = 2400 + 16,
	.vsync_end = 2400 + 16 + 2,
	.vtotal = 2400 + 16 + 2 + 2,
	.width_mm = 70,
	.height_mm = 155,
	.type = DRM_MODE_TYPE_DRIVER,
};

static int ams628rf05_get_modes(struct drm_panel *panel,
				struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector, &ams628rf05_mode);
}

static const struct drm_panel_funcs ams628rf05_panel_funcs = {
	.prepare = ams628rf05_prepare,
	.unprepare = ams628rf05_unprepare,
	.get_modes = ams628rf05_get_modes,
};

static int ams628rf05_bl_update_status(struct backlight_device *bl)
{
	struct mipi_dsi_device *dsi = bl_get_data(bl);
	u16 brightness = backlight_get_brightness(bl);
	int ret;

	dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;
	ret = mipi_dsi_dcs_set_display_brightness_large(dsi, brightness);
	dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	return ret < 0 ? ret : 0;
}

static const struct backlight_ops ams628rf05_bl_ops = {
	.update_status = ams628rf05_bl_update_status,
};

static struct backlight_device *
ams628rf05_create_backlight(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	const struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.brightness = 511,
		.max_brightness = 1023,
	};

	return devm_backlight_device_register(dev, dev_name(dev), dev, dsi,
					      &ams628rf05_bl_ops, &props);
}

static int ams628rf05_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct ams628rf05 *ctx;
	int ret;

	ctx = devm_drm_panel_alloc(dev, struct ams628rf05, panel,
				   &ams628rf05_panel_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);

	ret = devm_regulator_bulk_get_const(dev, ARRAY_SIZE(ams628rf05_supplies),
					    ams628rf05_supplies, &ctx->supplies);
	if (ret < 0)
		return dev_err_probe(dev, ret, "Failed to get regulators\n");

	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->enable_gpio = devm_gpiod_get_optional(dev, "enable", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->enable_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->enable_gpio),
				     "Failed to get enable-gpios\n");

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->mode_flags = MIPI_DSI_CLOCK_NON_CONTINUOUS | MIPI_DSI_MODE_LPM;

	ctx->panel.prepare_prev_first = true;

	ctx->panel.backlight = ams628rf05_create_backlight(dsi);
	if (IS_ERR(ctx->panel.backlight))
		return dev_err_probe(dev, PTR_ERR(ctx->panel.backlight),
				     "Failed to create backlight\n");

	drm_panel_add(&ctx->panel);

	ret = devm_mipi_dsi_attach(dev, dsi);
	if (ret < 0) {
		drm_panel_remove(&ctx->panel);
		return dev_err_probe(dev, ret, "Failed to attach to DSI host\n");
	}

	return 0;
}

static void ams628rf05_remove(struct mipi_dsi_device *dsi)
{
	struct ams628rf05 *ctx = mipi_dsi_get_drvdata(dsi);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id ams628rf05_of_match[] = {
	{ .compatible = "samsung,ams628rf05" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, ams628rf05_of_match);

static struct mipi_dsi_driver ams628rf05_driver = {
	.probe = ams628rf05_probe,
	.remove = ams628rf05_remove,
	.driver = {
		.name = "panel-samsung-ams628rf05",
		.of_match_table = ams628rf05_of_match,
	},
};
module_mipi_dsi_driver(ams628rf05_driver);

MODULE_DESCRIPTION("DRM driver for Samsung AMS628RF05 cmd mode DSI panel");
MODULE_LICENSE("GPL");
