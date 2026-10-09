// 文件职责：统计已付费的支持者人数，把订单去重到客户维度。
// 分层：Service（Polar SDK 查询）；全额退款的客户不计入，部分退款仍计入。

import type { PolarCore } from "@polar-sh/sdk/core.js";
import { ordersList } from "@polar-sh/sdk/funcs/ordersList.js";

// 全额退款会把该客户移出计数；部分退款不会。
const COUNTED_STATUSES = new Set<string>(["paid", "partially_refunded"]);

/** 同时购买任一支持者产品的去重客户数。 */
export async function countSupporters(
  polar: PolarCore,
  productIds: string[],
): Promise<number> {
  const customers = new Set<string>();
  const orders = await ordersList(polar, { productId: productIds, limit: 100 });
  for await (const page of orders) {
    if (!page.ok) throw page.error;
    for (const order of page.value.result.items) {
      if (COUNTED_STATUSES.has(order.status)) customers.add(order.customerId);
    }
  }
  return customers.size;
}
