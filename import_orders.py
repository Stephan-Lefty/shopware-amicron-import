#!/usr/bin/env python3
"""
Holt offene Bestellungen aus Shopware 6 per Admin-API und schreibt sie als
XML-Datei im Amicron-Faktura-Importformat (siehe Importdefinition 3) in den
von Faktura ueberwachten Import-Ordner.

Ablauf:
  1. OAuth2-Token bei Shopware holen (client_credentials)
  2. Offene Bestellungen inkl. Positionen, Adressen, Zahlart, Versandart abrufen
  3. XML gemaess Amicron-Importdefinition erzeugen
  4. Datei in den Faktura-Import-Ordner schreiben

Aufruf:  python import_orders.py [config.ini]
"""

import configparser
import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path
from xml.dom import minidom

import requests


def load_config(path):
    config = configparser.ConfigParser()
    if not Path(path).exists():
        sys.exit(f"Konfigurationsdatei nicht gefunden: {path}\n"
                  f"Kopiere config.ini.example zu config.ini und trage deine Zugangsdaten ein.")
    config.read(path, encoding="utf-8")
    return config["shopware"], config["faktura"]


def get_access_token(shop_url, client_id, client_secret):
    resp = requests.post(
        f"{shop_url}/api/oauth/token",
        json={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


ORDER_ASSOCIATIONS = {
    "lineItems": {},
    "billingAddress": {"associations": {"country": {}, "salutation": {}}},
    "deliveries": {
        "associations": {
            "shippingOrderAddress": {"associations": {"country": {}, "salutation": {}}},
            "shippingMethod": {},
        }
    },
    "orderCustomer": {},
    "currency": {},
    "transactions": {"associations": {"paymentMethod": {}}},
    "stateMachineState": {},
    "salesChannel": {},
}


def fetch_open_orders(shop_url, token, order_state):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    orders = []
    page = 1
    limit = 50
    while True:
        body = {
            "filter": [
                {
                    "type": "equals",
                    "field": "stateMachineState.technicalName",
                    "value": order_state,
                }
            ],
            "associations": ORDER_ASSOCIATIONS,
            "page": page,
            "limit": limit,
        }
        resp = requests.post(f"{shop_url}/api/search/order", json=body, headers=headers, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        batch = data.get("data", [])
        orders.extend(batch)
        total = data.get("meta", {}).get("total", len(orders))
        if not batch or len(orders) >= total:
            break
        page += 1
    return orders


def money(value):
    return f"{float(value or 0):.2f}"


def add_text(parent, name, value="", attrib=None):
    el = ET.SubElement(parent, name, attrib or {})
    el.text = "" if value is None else str(value)
    return el


def salutation_text(salutation):
    if isinstance(salutation, dict):
        return salutation.get("displayName") or ""
    return ""


# Feste Vorgaben fuer die Kundenverwaltung in Faktura (Reiter "Faktura"),
# unabhaengig von der tatsaechlichen Zahlart/Versandart der Bestellung.
KUNDE_ZAHLWEISE = "Vorkasse"
KUNDE_LIEFERART = "Paketdienst"


def build_address_node(parent, tag_name, address, new_data, email=None):
    address = address or {}
    node = ET.SubElement(parent, tag_name, {"NewData": new_data})
    add_text(node, "company", address.get("company"))
    add_text(node, "department", address.get("department"))
    add_text(node, "salutation", salutation_text(address.get("salutation")))
    add_text(node, "firstName", address.get("firstName"))
    add_text(node, "lastName", address.get("lastName"))
    add_text(node, "street", address.get("street"))
    add_text(node, "zipCode", address.get("zipcode"))
    add_text(node, "city", address.get("city"))
    if tag_name == "billing":
        add_text(node, "phone", address.get("phoneNumber"))
        add_text(node, "fax", "")
        add_text(node, "vatId", address.get("vatId"))
        add_text(node, "email", email or "")
        add_text(node, "kundeZahlweise", KUNDE_ZAHLWEISE)
        add_text(node, "kundeLieferart", KUNDE_LIEFERART)
    country = address.get("country") or {}
    add_text(node, "countryiso", country.get("iso"))
    return node


def line_item_tax_rate(line_item):
    price = line_item.get("price") or {}
    taxes = price.get("calculatedTaxes") or []
    if taxes:
        return taxes[0].get("taxRate", 0)
    return 0


def shipping_tax_rate(order):
    shipping_costs = order.get("shippingCosts") or {}
    taxes = shipping_costs.get("calculatedTaxes") or []
    if taxes:
        return taxes[0].get("taxRate", 0)
    return 0


SHIPPING_ARTICLE_NUMBER = "1000154"


def line_item_article_number(line_item):
    label = line_item.get("label") or ""
    if "versandkosten" in label.lower():
        return SHIPPING_ARTICLE_NUMBER
    payload = line_item.get("payload") or {}
    return payload.get("productNumber", "")


OPTION_GROUPS_EXCLUDED_FROM_ARTICLE_NAME = {"lieferung nach"}


def line_item_full_name(line_item):
    label = line_item.get("label") or ""
    payload = line_item.get("payload") or {}
    options = payload.get("options") or []
    parts = [
        f"{opt.get('group', '')}: {opt.get('option', '')}"
        for opt in options
        if opt.get("group") and opt.get("option")
        and opt.get("group", "").lower() not in OPTION_GROUPS_EXCLUDED_FROM_ARTICLE_NAME
    ]
    return f"{label} ({', '.join(parts)})" if parts else label


def latest_payment_method_name(order):
    transactions = order.get("transactions") or []
    if not transactions:
        return ""
    last = sorted(transactions, key=lambda t: t.get("createdAt") or "")[-1]
    method = last.get("paymentMethod") or {}
    return method.get("name", "")


def sales_channel_name(order):
    channel = order.get("salesChannel") or {}
    name = channel.get("name")
    if not name:
        name = (channel.get("translated") or {}).get("name")
    return name or ""


def build_order_element(order, shop_domain):
    order_number = order.get("orderNumber", "")
    order_el = ET.Element("ORDER")

    channel_name = sales_channel_name(order)
    number_value = f"{order_number} - {channel_name}" if channel_name else order_number

    add_text(order_el, "id", order_number, {"NewData": "AUFTRAG"})
    add_text(order_el, "number", number_value)
    add_text(order_el, "customerId", "")
    add_text(order_el, "invoiceAmount", money(order.get("amountTotal")))
    shipping_costs = order.get("shippingCosts") or {}
    add_text(order_el, "versandKosten", money(shipping_costs.get("totalPrice")))
    add_text(order_el, "invoiceShippingTax", shipping_tax_rate(order))

    order_datetime = order.get("orderDateTime", "")
    order_time_formatted = order_datetime
    order_date_only = ""
    if order_datetime:
        try:
            dt = datetime.fromisoformat(order_datetime)
            order_time_formatted = dt.strftime("%d.%m.%Y %H:%M:%S")
            order_date_only = dt.strftime("%d.%m.%Y")
        except ValueError:
            order_date_only = order_datetime.split("T")[0]
    add_text(order_el, "orderTime", order_time_formatted)
    add_text(order_el, "orderDatum", order_date_only)
    add_text(order_el, "shopURL", shop_domain)
    add_text(order_el, "comment", order.get("customerComment"))
    add_text(order_el, "internalComment", "")

    tax_status = order.get("taxStatus") or (order.get("price") or {}).get("taxStatus")
    add_text(order_el, "steuerInkl", "1" if tax_status == "gross" else "0")
    currency = order.get("currency") or {}
    add_text(order_el, "currency", currency.get("isoCode", "EUR"))

    details = ET.SubElement(order_el, "details")
    for line_item in order.get("lineItems") or []:
        if line_item.get("type") != "product":
            continue
        item = ET.SubElement(details, "item", {"NewData": "ATRPOS"})
        price = line_item.get("price") or {}
        full_name = line_item_full_name(line_item)
        add_text(item, "articleNumber", line_item_article_number(line_item))
        add_text(item, "price", money(price.get("unitPrice")))
        add_text(item, "quantity", line_item.get("quantity", 0))
        add_text(item, "articleName", full_name)
        add_text(item, "text", full_name)
        add_text(item, "taxRate", line_item_tax_rate(line_item))

    payment = ET.SubElement(order_el, "payment")
    add_text(payment, "description", latest_payment_method_name(order))

    order_customer = order.get("orderCustomer") or {}
    add_text(order_el, "groupKey", channel_name)
    add_text(order_el, "priceGroupId", "")

    debit = ET.SubElement(order_el, "debit")
    add_text(debit, "account", "")
    add_text(debit, "bankCode", "")
    add_text(debit, "bankName", "")
    add_text(debit, "accountHolder", "")

    build_address_node(
        order_el, "billing", order.get("billingAddress"), "KUNADRESSE",
        email=order_customer.get("email", ""),
    )

    deliveries = order.get("deliveries") or []
    shipping_address = deliveries[0].get("shippingOrderAddress") if deliveries else None
    build_address_node(order_el, "shipping", shipping_address, "LFRADRESSE")

    dispatch = ET.SubElement(order_el, "dispatch")
    add_text(dispatch, "name", "Paketdienst")

    return order_el


def build_orders_xml(orders, shop_domain):
    root = ET.Element("ORDERS")
    for order in orders:
        root.append(build_order_element(order, shop_domain))
    rough = ET.tostring(root, encoding="iso-8859-1")
    pretty = minidom.parseString(rough).toprettyxml(indent="    ", encoding="iso-8859-1")
    return pretty


def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).with_name("config.ini"))
    shopware_cfg, faktura_cfg = load_config(config_path)

    shop_url = shopware_cfg["shop_url"].rstrip("/")
    shop_domain = shop_url.replace("https://", "").replace("http://", "")

    print(f"Hole Access-Token von {shop_url} ...")
    token = get_access_token(shop_url, shopware_cfg["client_id"], shopware_cfg["client_secret"])

    print(f"Lade Bestellungen mit Status '{shopware_cfg['order_state']}' ...")
    orders = fetch_open_orders(shop_url, token, shopware_cfg["order_state"])
    print(f"{len(orders)} Bestellung(en) gefunden.")

    if not orders:
        print("Es sind keine neuen Bestellungen eingegangen!")
        return

    xml_bytes = build_orders_xml(orders, shop_domain)

    import_folder = Path(faktura_cfg["import_folder"])
    import_folder.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_file = import_folder / f"{faktura_cfg['file_prefix']}_{timestamp}.xml"
    out_file.write_bytes(xml_bytes)
    print(f"Geschrieben: {out_file}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Fehler: {exc}")
    input("\nFenster mit Enter schliessen ...")
