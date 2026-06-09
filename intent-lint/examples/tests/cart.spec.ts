import { test, expect } from '@playwright/test';

test('cart', async ({ page }) => {
  await expect(page).toBeTruthy();
});
