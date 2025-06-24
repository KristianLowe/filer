from fastapi import FastAPI, HTTPException
import os
import tempfile
import time
import sqlite3
import logging
from typing import Optional

logging.basicConfig(
    filename='/var/log/7sense/portalwebapi_py.log',
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)

try:
    from .portal_db import PortalDB  # when imported as package
except ImportError:  # pragma: no cover - direct execution
    from portal_db import PortalDB

app = FastAPI()

db = PortalDB()

@app.delete("/v1/customers/delete")
async def v1_customers_delete(customernumber: Optional[str] = None, customer_id: Optional[int] = None):
    """Delete a customer by number or id.

    Parameters:
        customernumber: textual customer identifier
        customer_id: numeric customer identifier

    Returns JSON ``{"message": "OK"}`` when the customer is removed.
    Responds with ``404`` if no matching record exists and ``400`` if no
    identifying parameter is provided.
    """
    if (customernumber is None or customernumber == "") and customer_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs customernumber or customer_id")

    if customernumber:
        where = "customernumber=?"
        params = (customernumber,)
        desc = f"customernumber='{customernumber}'"
    else:
        where = "customer_id=?"
        params = (customer_id,)
        desc = f"customer_id={customer_id}"

    rowcount = await db.execute(f"DELETE FROM customer WHERE {where}", params)
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No record for {desc}")
    return {"message": "OK"}


@app.get("/v1/customers/variable/list")
async def v1_customers_variable_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    customernumber: Optional[str] = None,
    variable: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List customer variables with optional filters."""

    base_query = (
        "SELECT customernumber, variable, value, dateupdated FROM customer_variables"
    )
    params: list = []
    where_clauses: list[str] = []
    if customernumber:
        where_clauses.append("customernumber=?")
        params.append(customernumber)
    if variable:
        where_clauses.append("variable=?")
        params.append(variable)
    query = base_query
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)

    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}

@app.patch("/v1/customers/variable/update")
async def v1_customers_variable_update(
    customernumber: Optional[str] = None,
    variable: Optional[str] = None,
    value: Optional[str] = None,
):
    """Update or create a customer variable."""
    if not customernumber or not variable or value is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs customernumber, variable and value",
        )
    rowcount = await db.execute(
        "UPDATE customer_variables SET value=? WHERE customernumber=? AND variable=?",
        (value, customernumber, variable),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO customer_variables (customernumber, variable, value) VALUES (?, ?, ?)",
            (customernumber, variable, value),
        )
    return {"result": "OK"}


@app.delete("/v1/customers/variable/delete")
async def v1_customers_variable_delete(
    customernumber: Optional[str] = None,
    variable: Optional[str] = None,
):
    """Delete a customer variable."""
    if customernumber is None and variable is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs productnumber, variable",
        )

    where_clauses = []
    params: list = []
    if customernumber is not None:
        where_clauses.append("customernumber=?")
        params.append(customernumber)
    if variable is not None:
        where_clauses.append("variable=?")
        params.append(variable)

    where_sql = ""
    if where_clauses:
        where_sql = " WHERE " + " AND ".join(where_clauses)

    rowcount = await db.execute(
        f"DELETE FROM customer_variables{where_sql}", tuple(params)
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No record for customernumber:{customernumber}, variable:{variable}",
        )
    return {"message": "OK"}


@app.get("/v1/helpdesks/list")
async def v1_helpdesks_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    helpdesknumber: Optional[str] = None,
    helpdesk_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List helpdesks with optional filters."""
    query = (
        "SELECT helpdesknumber,helpdesk_name,helpdesk_vatnumber,helpdesk_phone,"
        "helpdesk_fax,helpdesk_email,helpdesk_web,helpdesk_visitaddr1,"
        "helpdesk_visitaddr2,helpdesk_visitpostcode,helpdesk_visitcity,"
        "helpdesk_visitcountry,helpdesk_invoiceaddr1,helpdesk_invoiceaddr2,"
        "helpdesk_invoicepostcode,helpdesk_invoicecity,helpdesk_invoicecountry,"
        "helpdesk_deliveraddr1,helpdesk_deliveraddr2,helpdesk_deliverpostcode,"
        "helpdesk_delivercity,helpdesk_delivercountry,helpdesk_maincontact,"
        "helpdesk_deliveraddr_same_as_invoice,helpdesk_invoiceaddr_same_as_visit,"
        "helpdesk_id FROM helpdesks"
    )
    where_clauses: list[str] = []
    params: list = []
    if helpdesknumber:
        where_clauses.append("helpdesknumber=?")
        params.append(helpdesknumber)
    if helpdesk_id is not None:
        where_clauses.append("helpdesk_id=?")
        params.append(helpdesk_id)
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)

    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/helpdesks/add")
async def v1_helpdesks_add(
    helpdesknumber: Optional[str] = None,
    helpdesk_name: Optional[str] = "",
    helpdesk_vatnumber: Optional[str] = "",
    helpdesk_phone: Optional[str] = "",
    helpdesk_fax: Optional[str] = "",
    helpdesk_email: Optional[str] = "",
    helpdesk_web: Optional[str] = "",
    helpdesk_visitaddr1: Optional[str] = "",
    helpdesk_visitaddr2: Optional[str] = "",
    helpdesk_visitpostcode: Optional[str] = "",
    helpdesk_visitcity: Optional[str] = "",
    helpdesk_visitcountry: Optional[str] = "",
    helpdesk_invoiceaddr1: Optional[str] = "",
    helpdesk_invoiceaddr2: Optional[str] = "",
    helpdesk_invoicepostcode: Optional[str] = "",
    helpdesk_invoicecity: Optional[str] = "",
    helpdesk_invoicecountry: Optional[str] = "",
    helpdesk_deliveraddr1: Optional[str] = "",
    helpdesk_deliveraddr2: Optional[str] = "",
    helpdesk_deliverpostcode: Optional[str] = "",
    helpdesk_delivercity: Optional[str] = "",
    helpdesk_delivercountry: Optional[str] = "",
    helpdesk_maincontact: Optional[str] = "",
    helpdesk_deliveraddr_same_as_invoice: Optional[str] = "false",
    helpdesk_invoiceaddr_same_as_visit: Optional[str] = "false",
):
    """Insert a new helpdesk."""
    if not helpdesknumber:
        raise HTTPException(status_code=400, detail="Missing parameter: needs helpdesknumber")

    existing = await db.fetchone(
        "SELECT helpdesknumber FROM helpdesks WHERE helpdesknumber=?",
        (helpdesknumber,),
    )
    if existing:
        raise HTTPException(
            status_code=302,
            detail=f"Record exists for helpdesknumber:{helpdesknumber}",
        )

    await db.execute(
        """
        INSERT INTO helpdesks (
            helpdesknumber,helpdesk_name,helpdesk_vatnumber,helpdesk_phone,
            helpdesk_fax,helpdesk_email,helpdesk_web,helpdesk_visitaddr1,
            helpdesk_visitaddr2,helpdesk_visitpostcode,helpdesk_visitcity,
            helpdesk_visitcountry,helpdesk_invoiceaddr1,helpdesk_invoiceaddr2,
            helpdesk_invoicepostcode,helpdesk_invoicecity,helpdesk_invoicecountry,
            helpdesk_deliveraddr1,helpdesk_deliveraddr2,helpdesk_deliverpostcode,
            helpdesk_delivercity,helpdesk_delivercountry,helpdesk_maincontact,
            helpdesk_deliveraddr_same_as_invoice,helpdesk_invoiceaddr_same_as_visit
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """,
        (
            helpdesknumber,
            helpdesk_name,
            helpdesk_vatnumber,
            helpdesk_phone,
            helpdesk_fax,
            helpdesk_email,
            helpdesk_web,
            helpdesk_visitaddr1,
            helpdesk_visitaddr2,
            helpdesk_visitpostcode,
            helpdesk_visitcity,
            helpdesk_visitcountry,
            helpdesk_invoiceaddr1,
            helpdesk_invoiceaddr2,
            helpdesk_invoicepostcode,
            helpdesk_invoicecity,
            helpdesk_invoicecountry,
            helpdesk_deliveraddr1,
            helpdesk_deliveraddr2,
            helpdesk_deliverpostcode,
            helpdesk_delivercity,
            helpdesk_delivercountry,
            helpdesk_maincontact,
            helpdesk_deliveraddr_same_as_invoice,
            helpdesk_invoiceaddr_same_as_visit,
        ),
    )
    return {"result": "OK"}


@app.patch("/v1/helpdesks/update")
async def v1_helpdesks_update(
    helpdesknumber: Optional[str] = None,
    helpdesk_id: Optional[int] = None,
    helpdesk_name: Optional[str] = None,
    helpdesk_vatnumber: Optional[str] = None,
    helpdesk_phone: Optional[str] = None,
    helpdesk_fax: Optional[str] = None,
    helpdesk_email: Optional[str] = None,
    helpdesk_web: Optional[str] = None,
    helpdesk_visitaddr1: Optional[str] = None,
    helpdesk_visitaddr2: Optional[str] = None,
    helpdesk_visitpostcode: Optional[str] = None,
    helpdesk_visitcity: Optional[str] = None,
    helpdesk_visitcountry: Optional[str] = None,
    helpdesk_invoiceaddr1: Optional[str] = None,
    helpdesk_invoiceaddr2: Optional[str] = None,
    helpdesk_invoicepostcode: Optional[str] = None,
    helpdesk_invoicecity: Optional[str] = None,
    helpdesk_invoicecountry: Optional[str] = None,
    helpdesk_deliveraddr1: Optional[str] = None,
    helpdesk_deliveraddr2: Optional[str] = None,
    helpdesk_deliverpostcode: Optional[str] = None,
    helpdesk_delivercity: Optional[str] = None,
    helpdesk_delivercountry: Optional[str] = None,
    helpdesk_maincontact: Optional[str] = None,
    helpdesk_deliveraddr_same_as_invoice: Optional[str] = None,
    helpdesk_invoiceaddr_same_as_visit: Optional[str] = None,
):
    """Update helpdesk information."""
    if helpdesknumber is None and helpdesk_id is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs helpdesknumber or helpdesk_id",
        )

    updates = []
    params: list = []
    for column, value in [
        ("helpdesk_name", helpdesk_name),
        ("helpdesk_vatnumber", helpdesk_vatnumber),
        ("helpdesk_phone", helpdesk_phone),
        ("helpdesk_fax", helpdesk_fax),
        ("helpdesk_email", helpdesk_email),
        ("helpdesk_web", helpdesk_web),
        ("helpdesk_visitaddr1", helpdesk_visitaddr1),
        ("helpdesk_visitaddr2", helpdesk_visitaddr2),
        ("helpdesk_visitpostcode", helpdesk_visitpostcode),
        ("helpdesk_visitcity", helpdesk_visitcity),
        ("helpdesk_visitcountry", helpdesk_visitcountry),
        ("helpdesk_invoiceaddr1", helpdesk_invoiceaddr1),
        ("helpdesk_invoiceaddr2", helpdesk_invoiceaddr2),
        ("helpdesk_invoicepostcode", helpdesk_invoicepostcode),
        ("helpdesk_invoicecity", helpdesk_invoicecity),
        ("helpdesk_invoicecountry", helpdesk_invoicecountry),
        ("helpdesk_deliveraddr1", helpdesk_deliveraddr1),
        ("helpdesk_deliveraddr2", helpdesk_deliveraddr2),
        ("helpdesk_deliverpostcode", helpdesk_deliverpostcode),
        ("helpdesk_delivercity", helpdesk_delivercity),
        ("helpdesk_delivercountry", helpdesk_delivercountry),
        ("helpdesk_maincontact", helpdesk_maincontact),
        ("helpdesk_deliveraddr_same_as_invoice", helpdesk_deliveraddr_same_as_invoice),
        ("helpdesk_invoiceaddr_same_as_visit", helpdesk_invoiceaddr_same_as_visit),
    ]:
        if value is not None:
            updates.append(f"{column}=?")
            params.append(value)

    if not updates:
        raise HTTPException(
            status_code=400,
            detail=(
                "Missing parameter: needs at least one: helpdesk_name,helpdesk_vatnumber,helpdesk_phone,helpdesk_fax,"
                "helpdesk_email,helpdesk_web,helpdesk_visitaddr1,helpdesk_visitaddr2,helpdesk_visitpostcode,"
                "helpdesk_visitcity,helpdesk_visitcountry,helpdesk_invoiceaddr1,helpdesk_invoiceaddr2,"
                "helpdesk_invoicepostcode,helpdesk_invoicecity,helpdesk_invoicecountry,helpdesk_deliveraddr1,"
                "helpdesk_deliveraddr2,helpdesk_deliverpostcode,helpdesk_delivercity,helpdesk_delivercountry,"
                "helpdesk_maincontact,helpdesk_deliveraddr_same_as_invoice,helpdesk_invoiceaddr_same_as_visit"
            ),
        )

    if helpdesknumber:
        where = "helpdesknumber=?"
        where_param = helpdesknumber
    else:
        where = "helpdesk_id=?"
        where_param = helpdesk_id

    params.append(where_param)
    rowcount = await db.execute(
        f"UPDATE helpdesks SET {', '.join(updates)} WHERE {where}", tuple(params)
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"Missing record for helpdesknumber:{helpdesknumber}",
        )
    return {"result": "OK"}


@app.delete("/v1/helpdesks/delete")
async def v1_helpdesks_delete(
    helpdesknumber: Optional[str] = None,
    helpdesk_id: Optional[int] = None,
):
    """Delete a helpdesk by number or id."""
    if (helpdesknumber is None or helpdesknumber == "") and helpdesk_id is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs helpdesknumber or helpdesk_id",
        )

    if helpdesknumber:
        where = "helpdesknumber=?"
        param = helpdesknumber
        desc = f"helpdesknumber='{helpdesknumber}'"
    else:
        where = "helpdesk_id=?"
        param = helpdesk_id
        desc = f"helpdesk_id={helpdesk_id}"

    rowcount = await db.execute(f"DELETE FROM helpdesks WHERE {where}", (param,))
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No record for {desc}")
    return {"message": "OK"}


@app.get("/v1/messages/list")
async def v1_messages_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    customernumber: Optional[str] = None,
    customer_id_ref: Optional[int] = None,
    serialnumber: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List messages joined with customer data."""
    query = (
        "SELECT archived,message,timestamp,checkedbyuser,serialnumber,message_id,"
        "customer.customer_id,customer.customernumber FROM messages "
        "INNER JOIN customer ON (customer.customer_id = customer_id_ref)"
    )
    where_clauses: list[str] = []
    params: list = []

    if customernumber is not None:
        clause = "customer.customernumber=?"
        params.append(customernumber)
        if serialnumber is not None:
            clause += " AND serialnumber=?"
            params.append(serialnumber)
        where_clauses.append(clause)
    elif customer_id_ref is not None:
        clause = "customer_id_ref=?"
        params.append(customer_id_ref)
        if serialnumber is not None:
            clause += " AND serialnumber=?"
            params.append(serialnumber)
        where_clauses.append(clause)
    elif serialnumber is not None:
        where_clauses.append("serialnumber=?")
        params.append(serialnumber)

    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)

    if sortfield:
        query += f" ORDER BY {sortfield}"
    else:
        query += " ORDER BY timestamp desc"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)

    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}
@app.post("/v1/messages/add")
async def v1_messages_add(
    message: Optional[str] = None,
    serialnumber: Optional[str] = None,
    customernumber: Optional[str] = None,
    customer_id_ref: Optional[int] = None,
):
    """Insert a new message entry."""
    if not message or not serialnumber or (customernumber is None and customer_id_ref is None):
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs message, serialnumber, (customernumber or customer_id_ref)",
        )
    if customernumber is not None:
        row = await db.fetchone(
            "SELECT customer_id FROM customer WHERE customernumber=?",
            (customernumber,),
        )
        if row is None:
            raise HTTPException(
                status_code=302,
                detail=f"Record does not exists for customernumber:{customernumber}",
            )
        customer_id_ref = row["customer_id"]
    await db.execute(
        "INSERT INTO messages (customer_id_ref, serialnumber, message) VALUES (?, ?, ?)",
        (customer_id_ref, serialnumber, message),
    )
    return {"result": "OK"}


@app.patch("/v1/messages/update")
async def v1_messages_update(
    message_id: Optional[int] = None,
    archived: Optional[str] = None,
    checkedbyuser: Optional[str] = None,
):
    """Update message archive and checked status."""
    if message_id is None or archived is None or checkedbyuser is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs message_id, archived, checkedbyuser",
        )
    rowcount = await db.execute(
        "UPDATE messages SET archived=?, checkedbyuser=? WHERE message_id=?",
        (archived, checkedbyuser, message_id),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=302,
            detail=f"Record does not exists for message_id:{message_id}",
        )
    return {"result": "OK"}


@app.delete("/v1/messages/delete")
async def v1_messages_delete(message_id: Optional[int] = None):
    """Delete a message by id."""
    if message_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs message_id")
    rowcount = await db.execute("DELETE FROM messages WHERE message_id=?", (message_id,))
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No record for message_id:{message_id}")
    return {"message": "OK"}


@app.get("/v1/customertypes/list")
async def v1_customertypes_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List customer types."""
    query = "SELECT customertype,description,customertype_id FROM customertype"
    params: list = []
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/customertypes/add")
async def v1_customertypes_add(customertype: Optional[str] = None, description: Optional[str] = None):
    """Add a new customer type."""
    if customertype is None or description is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs customertype and description")
    await db.execute(
        "INSERT INTO customertype (customertype, description) VALUES (?, ?)",
        (customertype, description),
    )
    return {"result": "OK"}


@app.patch("/v1/customertypes/update")
async def v1_customertypes_update(
    customertype_id: Optional[int] = None,
    customertype: Optional[str] = None,
    description: Optional[str] = None,
):
    """Update an existing customer type."""
    if customertype_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs customertype_id")

    updates = []
    params: list = []
    if description is not None:
        updates.append("description=?")
        params.append(description)
    if customertype is not None:
        updates.append("customertype=?")
        params.append(customertype)
    if not updates:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs at least one: customertype, description",
        )
    params.append(customertype_id)
    rowcount = await db.execute(
        f"UPDATE customertype SET {', '.join(updates)} WHERE customertype_id=?",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=302,
            detail=f"Record does not exists for customertype_id:{customertype_id}",
        )
    return {"result": "OK"}


@app.delete("/v1/customertypes/delete")
async def v1_customertypes_delete(customertype_id: Optional[int] = None):
    """Delete a customer type."""
    if customertype_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs customertype_id")
    rowcount = await db.execute(
        "DELETE FROM customertype WHERE customertype_id=?",
        (customertype_id,),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No record for customertype_id:{customertype_id}",
        )
    return {"message": "OK"}


@app.get("/v1/gui/viewgroup/list")
async def v1_gui_viewgroup_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    customernumber: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List GUI viewgroups."""
    query = (
        "SELECT viewgroup_id, viewgroup_name, viewgroup_description, customernumber "
        "FROM gui_viewgroup"
    )
    params: list = []
    if customernumber is not None:
        query += " WHERE customernumber=?"
        params.append(customernumber)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/gui/viewgroup/add")
async def v1_gui_viewgroup_add(
    customernumber: Optional[str] = None,
    viewgroup_name: Optional[str] = None,
    viewgroup_description: Optional[str] = "",
):
    """Add a new GUI viewgroup."""
    if customernumber is None or viewgroup_name is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs customernumber and viewgroup_name. Option viewgroup_description",
        )
    existing = await db.fetchone(
        "SELECT viewgroup_name FROM gui_viewgroup WHERE customernumber=? AND viewgroup_name=?",
        (customernumber, viewgroup_name),
    )
    if existing:
        raise HTTPException(
            status_code=302,
            detail=(
                f"Record exists for customernumber:{customernumber} and viewgroup_name:{viewgroup_name}"
            ),
        )
    await db.execute(
        "INSERT INTO gui_viewgroup (customernumber, viewgroup_name, viewgroup_description) VALUES (?, ?, ?)",
        (customernumber, viewgroup_name, viewgroup_description or ""),
    )
    return {"result": "OK"}


@app.patch("/v1/gui/viewgroup/update")
async def v1_gui_viewgroup_update(
    viewgroup_id: Optional[int] = None,
    viewgroup_name: Optional[str] = None,
    viewgroup_description: Optional[str] = None,
):
    """Update a GUI viewgroup."""
    if viewgroup_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs viewgroup_id")

    updates = []
    params: list = []
    if viewgroup_name is not None:
        updates.append("viewgroup_name=?")
        params.append(viewgroup_name)
    if viewgroup_description is not None:
        updates.append("viewgroup_description=?")
        params.append(viewgroup_description)
    if not updates:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs at least one: viewgroup_name, viewgroup_description",
        )
    params.append(viewgroup_id)
    rowcount = await db.execute(
        f"UPDATE gui_viewgroup SET {', '.join(updates)} WHERE viewgroup_id=?",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"Missing record for viewgroup_id:{viewgroup_id}. Please add first",
        )
    return {"result": "OK"}


@app.delete("/v1/gui/viewgroup/delete")
async def v1_gui_viewgroup_delete(viewgroup_id: Optional[int] = None):
    """Delete a GUI viewgroup."""
    if viewgroup_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs viewgroup_id")
    rowcount = await db.execute(
        "DELETE FROM gui_viewgroup WHERE viewgroup_id=?",
        (viewgroup_id,),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=302,
            detail=f"No record for viewgroup_id:{viewgroup_id}",
        )
    return {"message": "OK"}


@app.get("/v1/gui/viewgroup/order/list")
async def v1_gui_viewgroup_order_list(
    serialnumber: Optional[str] = None,
    customernumber: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List GUI viewgroup order records."""
    query = (
        "SELECT viewgroup_order_id, serialnumber, viewgroup_id_ref, viewgroup_order, "
        "viewgroup_id, viewgroup_name, viewgroup_description, customernumber "
        "FROM gui_viewgroup_order INNER JOIN gui_viewgroup ON (viewgroup_id_ref = viewgroup_id)"
    )
    where_clauses = []
    params: list = []
    if serialnumber is not None:
        where_clauses.append("serialnumber=?")
        params.append(serialnumber)
    if customernumber is not None:
        where_clauses.append("customernumber=?")
        params.append(customernumber)
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    else:
        query += " ORDER BY viewgroup_order"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/gui/viewgroup/order/add")
async def v1_gui_viewgroup_order_add(
    serialnumber: Optional[str] = None,
    viewgroup_id_ref: Optional[int] = None,
    viewgroup_order: Optional[int] = None,
):
    """Add a GUI viewgroup order."""
    if not serialnumber or viewgroup_id_ref is None or viewgroup_order is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs serialnumber, viewgroup_id_ref and viewgroup_order",
        )
    existing = await db.fetchone(
        "SELECT viewgroup_order_id FROM gui_viewgroup_order WHERE serialnumber=?",
        (serialnumber,),
    )
    if existing:
        raise HTTPException(
            status_code=302,
            detail=f"Record viewgroup_order exists for serialnumber:{serialnumber}",
        )
    await db.execute(
        "INSERT INTO gui_viewgroup_order (serialnumber, viewgroup_id_ref, viewgroup_order) VALUES (?, ?, ?)",
        (serialnumber, viewgroup_id_ref, viewgroup_order),
    )
    return {"result": "OK"}


@app.patch("/v1/gui/viewgroup/order/update")
async def v1_gui_viewgroup_order_update(
    viewgroup_order_id: Optional[int] = None,
    serialnumber: Optional[str] = None,
    viewgroup_id_ref: Optional[int] = None,
    viewgroup_order: Optional[int] = None,
):
    """Update GUI viewgroup order."""
    if viewgroup_order_id is None and serialnumber is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs viewgroup_order_id or serialnumber. Option: viewgroup_id_ref and/or viewgroup_order",
        )
    updates = []
    params: list = []
    if viewgroup_id_ref is not None:
        updates.append("viewgroup_id_ref=?")
        params.append(viewgroup_id_ref)
    if viewgroup_order is not None:
        updates.append("viewgroup_order=?")
        params.append(viewgroup_order)
    if not updates:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs at least one: viewgroup_id_ref, viewgroup_order",
        )
    if viewgroup_order_id is not None:
        where = "viewgroup_order_id=?"
        params.append(viewgroup_order_id)
    else:
        where = "serialnumber=?"
        params.append(serialnumber)
    rowcount = await db.execute(
        f"UPDATE gui_viewgroup_order SET {', '.join(updates)} WHERE {where}",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"Missing record for viewgroup_order_id:{viewgroup_order_id} or serialnumber:{serialnumber}",
        )
    return {"result": "OK"}


@app.delete("/v1/gui/viewgroup/order/delete")
async def v1_gui_viewgroup_order_delete(
    viewgroup_order_id: Optional[int] = None,
    serialnumber: Optional[str] = None,
):
    """Delete GUI viewgroup order."""
    if viewgroup_order_id is None and serialnumber is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs viewgroup_id or serialnumber",
        )
    if viewgroup_order_id is not None:
        where = "viewgroup_order_id=?"
        param = viewgroup_order_id
    else:
        where = "serialnumber=?"
        param = serialnumber
    rowcount = await db.execute(
        f"DELETE FROM gui_viewgroup_order WHERE {where}",
        (param,),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=302,
            detail=f"No record for {where.replace('=?', '=' + str(param))}",
        )
    return {"message": "OK"}


@app.get("/v1/variabletypes/list")
async def v1_variabletypes_list(
    variables_types_type: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List variable types."""
    query = "SELECT variable_types_variable, variable_types_type, variable_types_defaultvalue, variable_types_dateupdated FROM variable_types"
    params: list = []
    if variables_types_type is not None:
        query += " WHERE variable_types_type = ?"
        params.append(variables_types_type)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.get("/v1/countries/list")
async def v1_countries_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    country_id: Optional[int] = None,
    variable: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List countries."""
    query = "SELECT country_id, name FROM countries"
    params: list = []
    if country_id is not None:
        query += " WHERE country_id=?"
        params.append(country_id)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.patch("/v1/sensordata/rename")
async def v1_sensordata_rename(dbname: Optional[str] = None):
    """Rename sensornumber column to probenumber in a sensordata DB."""
    if not dbname:
        raise HTTPException(status_code=400, detail="Missing parameter, needs dbname")
    try:
        conn = sqlite3.connect(dbname)
        conn.execute("ALTER TABLE sensordata RENAME COLUMN sensornumber TO probenumber")
        conn.commit()
        conn.close()
    except Exception:
        raise HTTPException(status_code=400, detail=f"Did not update:{dbname}")
    return {"message": "OK"}


@app.patch("/v1/sensorunit/move2customer")
async def v1_sensorunit_move2customer(
    serialnumber: Optional[str] = None,
    customernumber: Optional[str] = None,
):
    """Move a sensorunit to another customer."""
    if not serialnumber or not customernumber:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs serialnumber and customernumber",
        )
    row = await db.fetchone(
        "SELECT sensorunit_id, customernumber FROM sensorunits WHERE serialnumber=?",
        (serialnumber,),
    )
    if row is None:
        raise HTTPException(status_code=400, detail=f"Did not find serialnumber: {serialnumber}")
    if row["customernumber"] == customernumber:
        return {"message": "No change needed"}
    sensorunit_id = row["sensorunit_id"]
    await db.execute("DELETE FROM sensoraccess WHERE serialnumber=?", (serialnumber,))
    await db.execute("DELETE FROM message_receivers WHERE sensorunits_id_ref=?", (sensorunit_id,))
    await db.execute("DELETE FROM gui_viewgroup_order WHERE serialnumber=?", (serialnumber,))
    row = await db.fetchone(
        "SELECT customer_id FROM customer WHERE customernumber=?",
        (customernumber,),
    )
    if row is None:
        raise HTTPException(status_code=400, detail=f"Did not find customernumber: {customernumber}")
    customer_id = row["customer_id"]
    users = await db.fetchall(
        "SELECT user_id FROM users WHERE customer_id_ref=?",
        (customer_id,),
    )
    for u in users:
        await db.execute(
            "INSERT INTO sensoraccess (user_id, serialnumber, changeallowed) VALUES (?, ?, 'true')",
            (u["user_id"], serialnumber),
        )
        await db.execute(
            "INSERT INTO message_receivers (users_id_ref, sensorunits_id_ref) VALUES (?, ?)",
            (u["user_id"], sensorunit_id),
        )
    database_name = "sensordata_" + customernumber[3:7]
    await db.execute(
        "UPDATE sensorunits SET customernumber=?, customer_id_ref=?, dbname=? WHERE serialnumber=?",
        (customernumber, customer_id, database_name, serialnumber),
    )
    return {"message": "OK"}


@app.post("/v1/sensordata/add")
async def v1_sensordata_add(
    serialnumber: Optional[str] = None,
    sensordata: Optional[str] = None,
    payloadversion: Optional[int] = 0,
    timestamp: Optional[int] = None,
    packagecounter: Optional[int] = 0,
):
    """Add sensordata entry (writes to a temp file)."""
    if not serialnumber or not sensordata:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber and sensordata")
    ts = timestamp or int(time.time())
    combined = f"{ts},{serialnumber},{sensordata},{packagecounter}"
    fd, path = tempfile.mkstemp(prefix=serialnumber, dir="/tmp")
    with os.fdopen(fd, "w") as f:
        f.write(combined)
    return {"result": "OK"}



@app.post("/v1/event/add")
async def v1_event_add(
    serialnumber: Optional[str] = None,
    event: Optional[str] = None,
    username: Optional[str] = "",
    userid: Optional[str] = "",
):
    """Register an event for a serialnumber."""
    if not serialnumber or not event:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter, needs serialnumber and event with option username/userid",
        )
    return {"message": "OK"}


@app.post("/v1/sendsms")
async def v1_sendsms(mobilnumber: Optional[str] = None, text: Optional[str] = None):
    """Send an SMS message (stubbed)."""
    if not mobilnumber or not text:
        raise HTTPException(status_code=400, detail="Missing parameter, needs mobilnumber and text")
    return {"result": "OK"}


@app.post("/v1/sendmessage")
async def v1_sendmessage(
    serialnumber: Optional[str] = None,
    sensorunit_id: Optional[int] = None,
    user_id: Optional[int] = None,
    mailmessage: Optional[str] = None,
    mailsubject: Optional[str] = "Message from 7sense",
    smsmessage: Optional[str] = None,
    pushmessage: Optional[str] = None,
):
    """Send a message to one or more users (simplified)."""
    if not serialnumber and sensorunit_id is None and user_id is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Missing parameter: needs serialnumber or sensorunit_id or user_id. "
                "Option mailmessage, mailsubject, smsmessage, pushmessage"
            ),
        )
    recipients: list[int] = []
    if user_id is not None:
        recipients.append(user_id)
    else:
        if sensorunit_id is None and serialnumber:
            row = await db.fetchone(
                "SELECT sensorunit_id FROM sensorunits WHERE serialnumber=?",
                (serialnumber,),
            )
            if row is None:
                raise HTTPException(status_code=400, detail=f"Serialnumber {serialnumber} is missing in DB")
            sensorunit_id = row["sensorunit_id"]
        if sensorunit_id is not None:
            rows = await db.fetchall(
                "SELECT users_id_ref FROM message_receivers where sensorunits_id_ref=?",
                (sensorunit_id,),
            )
            recipients = [r["users_id_ref"] for r in rows]
    return {"result": "OK", "messages": len(recipients)}


@app.post("/v1/pushmessage")
async def v1_pushmessage(
    serialnumber: Optional[str] = None,
    sensorunit_id: Optional[int] = None,
    user_id: Optional[int] = None,
    message: Optional[str] = None,
    subject: Optional[str] = "Message from 7sense",
):
    """Send a push notification (simplified)."""
    if (not serialnumber and sensorunit_id is None and user_id is None) or message is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter, needs message and (serialnumber or sensorunit_id or user_id) with option subject",
        )
    recipients: list[int] = []
    if user_id is not None:
        recipients.append(user_id)
    else:
        if sensorunit_id is None and serialnumber:
            row = await db.fetchone(
                "SELECT sensorunit_id FROM sensorunits WHERE serialnumber=?",
                (serialnumber,),
            )
            if row is None:
                raise HTTPException(status_code=400, detail=f"Serialnumber {serialnumber} is missing")
            sensorunit_id = row["sensorunit_id"]
        if sensorunit_id is not None:
            rows = await db.fetchall(
                "SELECT users_id_ref FROM message_receivers where sensorunits_id_ref=?",
                (sensorunit_id,),
            )
            recipients = [r["users_id_ref"] for r in rows]
    return {"result": "OK", "messages": len(recipients)}


async def dbget_variable(serialnumber: str, variable: str):
    row = await db.fetchone(
        "SELECT value FROM sensorunit_variables WHERE serialnumber=? AND variable=?",
        (serialnumber, variable),
    )
    return row["value"] if row else None


async def dbupdate_variable(serialnumber: str, variable: str, value: str) -> None:
    count = await db.execute(
        "UPDATE sensorunit_variables SET value=? WHERE serialnumber=? AND variable=?",
        (value, serialnumber, variable),
    )
    if count == 0:
        await db.execute(
            "INSERT INTO sensorunit_variables (serialnumber, variable, value) VALUES (?, ?, ?)",
            (serialnumber, variable, value),
        )


@app.patch("/v1/sensorunit/ports/output/on")
async def v1_sensorunit_ports_output_on(serialnumber: Optional[str] = None, port: Optional[int] = None):
    """Activate a relay port."""
    if not serialnumber or port is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber and port")
    phone = await dbget_variable(serialnumber, "remotecontroller_phonenumber")
    if phone is None:
        raise HTTPException(status_code=400, detail="Missing remotecontroller_phonenumber or empty")
    status_str = await dbget_variable(serialnumber, "remotecontroller_status") or "2,0,2,0"
    parts = status_str.split(",")
    updated = int(time.time())
    if port == 1:
        new_status = f"3,{updated},{parts[2]},{parts[3]}"
    else:
        new_status = f"{parts[0]},{parts[1]},3,{updated}"
    await dbupdate_variable(serialnumber, "remotecontroller_status", new_status)
    return {"result": "OK"}


@app.patch("/v1/sensorunit/ports/output/off")
async def v1_sensorunit_ports_output_off(serialnumber: Optional[str] = None, port: Optional[int] = None):
    """Deactivate a relay port."""
    if not serialnumber or port is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber and port")
    phone = await dbget_variable(serialnumber, "remotecontroller_phonenumber")
    if phone is None:
        raise HTTPException(status_code=400, detail="Missing remotecontroller_phonenumber or empty")
    status_str = await dbget_variable(serialnumber, "remotecontroller_status") or "2,0,2,0"
    parts = status_str.split(",")
    updated = int(time.time())
    if port == 1:
        new_status = f"4,{updated},{parts[2]},{parts[3]}"
    else:
        new_status = f"{parts[0]},{parts[1]},4,{updated}"
    await dbupdate_variable(serialnumber, "remotecontroller_status", new_status)
    return {"result": "OK"}


@app.get("/v1/sensorunit/ports/output/status")
async def v1_sensorunit_ports_output_status(serialnumber: Optional[str] = None):
    """Return relay port status information."""
    if not serialnumber:
        raise HTTPException(status_code=400, detail="Missing parameter, needs serialnumber")
    config = await dbget_variable(serialnumber, "remotecontroller_config") or "0,0,0"
    status = await dbget_variable(serialnumber, "remotecontroller_status") or "0,0,0,0"
    port_numbers, *activated = config.split(",")
    status_parts = status.split(",")
    result = []
    port = 1
    for state in activated:
        if state:
            stat = status_parts[(port - 1) * 2]
            updated_at = status_parts[(port - 1) * 2 + 1]
            result.append({"port": str(port), "status": stat, "updated_at": updated_at})
        port += 1
    return {"result": result}


@app.post("/v1/customers/add")
async def v1_customers_add(
    customernumber: Optional[str] = None,
    customer_name: Optional[str] = "",
    customertype_id_ref: Optional[int] = 1,
):
    """Insert a new customer."""
    if not customernumber:
        raise HTTPException(status_code=400, detail="Missing parameter: needs customernumber")
    row = await db.fetchone(
        "SELECT customernumber FROM customer WHERE customernumber=?",
        (customernumber,),
    )
    if row:
        raise HTTPException(status_code=302, detail=f"Record exists for customernumber:{customernumber}")
    await db.execute(
        "INSERT INTO customer (customernumber, customer_name, customertype_id_ref) VALUES (?, ?, ?)",
        (customernumber, customer_name or "", customertype_id_ref),
    )
    return {"result": "OK"}


@app.get("/v1/customers/list")
async def v1_customers_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    customernumber: Optional[str] = None,
    customer_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List customers with optional filters."""
    query = (
        "SELECT customer.customernumber, customer.customer_name, customer.customer_id,"
        " customertype.customertype, customertype.description "
        "FROM customer INNER JOIN customertype ON customer.customertype_id_ref = customertype.customertype_id"
    )
    where_clauses: list[str] = []
    params: list = []
    if customernumber:
        where_clauses.append("customer.customernumber=?")
        params.append(customernumber)
    if customer_id is not None:
        where_clauses.append("customer.customer_id=?")
        params.append(customer_id)
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.patch("/v1/customers/update")
async def v1_customers_update(
    customernumber: Optional[str] = None,
    customer_id: Optional[int] = None,
    customer_name: Optional[str] = None,
    customertype_id_ref: Optional[int] = None,
):
    """Update customer details."""
    if (not customernumber and customer_id is None):
        raise HTTPException(status_code=400, detail="Missing parameter: needs customernumber or customer_id")
    updates = []
    params: list = []
    if customer_name is not None:
        updates.append("customer_name=?")
        params.append(customer_name)
    if customertype_id_ref is not None:
        updates.append("customertype_id_ref=?")
        params.append(customertype_id_ref)
    if not updates:
        raise HTTPException(status_code=400, detail="Missing parameter: needs at least one: customer_name, customertype_id_ref")
    if customernumber:
        where = "customernumber=?"
        params.append(customernumber)
    else:
        where = "customer_id=?"
        params.append(customer_id)
    rowcount = await db.execute(
        f"UPDATE customer SET {', '.join(updates)} WHERE {where}",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(status_code=404, detail="No record for customer")
    return {"result": "OK"}


@app.get("/v1/document/list")
async def v1_document_list(
    limit: Optional[int] = None,
    page: Optional[int] = None,
    serialnumber: Optional[str] = None,
    language: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List documents."""
    query = (
        "SELECT document_id,document_name,document_url,document_language,document_version,document_regdate,document_updated FROM documents"
    )
    where = []
    params: list = []
    if language and not serialnumber:
        where.append("document_language=?")
        params.append(language)
    if serialnumber and not language:
        where.append("serialnumber=?")
        params.append(serialnumber)
    if serialnumber and language:
        where.append("serialnumber=? AND document_language=?")
        params.extend([serialnumber, language])
    if where:
        query += " WHERE " + " AND ".join(where)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
        if page is not None and page > 0:
            query += " OFFSET ?"
            params.append((page - 1) * limit)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/document/add")
async def v1_document_add(
    document_name: Optional[str] = None,
    document_url: Optional[str] = None,
    document_language: Optional[str] = "",
    document_version: Optional[str] = "",
    serialnumber: Optional[str] = None,
):
    """Insert a new document."""
    if not document_name or not document_url:
        raise HTTPException(status_code=400, detail="Missing parameter: needs document_name and document_url")
    await db.execute(
        "INSERT INTO documents (document_name, document_url, document_language, document_version, serialnumber) VALUES (?, ?, ?, ?, ?)",
        (document_name, document_url, document_language or "", document_version or "", serialnumber),
    )
    return {"result": "OK"}


@app.delete("/v1/document/delete")
async def v1_document_delete(document_id: Optional[int] = None):
    """Remove a document."""
    if document_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs document_id")
    rowcount = await db.execute("DELETE FROM documents WHERE document_id=?", (document_id,))
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No document id for id:{document_id}")
    return {"message": "OK"}


@app.get("/v1/irrigation/runlog/list")
async def v1_irrigation_runlog_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    serialnumber: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List irrigation run log entries."""
    if not serialnumber:
        raise HTTPException(status_code=400, detail="Missing parameter, needs serialnumber")
    query = (
        "SELECT serialnumber,irrigation_starttime,irrigation_endtime,irrigation_startpoint,irrigation_endpoint,irrigation_nozzlewidth,irrigation_nozzlebar,irrigation_run_id,irrigation_note,hidden,irrigation_nozzleadjustment,portal_endpoint FROM irrigation_log WHERE serialnumber=?"
    )
    params: list = [serialnumber]
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.patch("/v1/irrigation/runlog/update")
async def v1_irrigation_runlog_update(
    serialnumber: Optional[str] = None,
    irrigation_run_id: Optional[int] = None,
    hidden: Optional[str] = None,
    portal_endpoint: Optional[str] = None,
):
    """Update irrigation run log fields."""
    if not serialnumber or irrigation_run_id is None or (hidden is None and portal_endpoint is None):
        raise HTTPException(
            status_code=400,
            detail="Missing parameter, needs serialnumber, irrigation_run_id and (hidden or portal_endpoint)",
        )
    updates = []
    params: list = []
    if hidden is not None:
        updates.append("hidden=?")
        params.append(hidden)
    if portal_endpoint is not None:
        updates.append("portal_endpoint=?")
        params.append(portal_endpoint)
    params.extend([serialnumber, irrigation_run_id])
    rowcount = await db.execute(
        f"UPDATE irrigation_log SET {', '.join(updates)} WHERE serialnumber=? AND irrigation_run_id=?",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"Record for serialnumber:{serialnumber}, irrigation_run_id:{irrigation_run_id} do not exists",
        )
    return {"result": "OK"}


@app.delete("/v1/products/delete")
async def v1_products_delete(productnumber: Optional[str] = None, product_id: Optional[int] = None):
    """Delete a product."""
    if not productnumber and product_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs productnumber or product_id")
    if productnumber:
        where = "productnumber=?"
        param = productnumber
    else:
        where = "product_id=?"
        param = product_id
    rowcount = await db.execute(f"DELETE FROM products WHERE {where}", (param,))
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No record for for productnumber:{productnumber} or product_id:{product_id}")
    return {"message": "OK"}


@app.get("/v1/products/list")
async def v1_products_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    productnumber: Optional[str] = None,
    product_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List products."""
    query = (
        "SELECT product_id,productnumber, product_name, product_description,product_type,product_image_url,document_id_ref FROM products"
    )
    where_clauses: list[str] = []
    params: list = []
    if productnumber is not None:
        where_clauses.append("productnumber=?")
        params.append(productnumber)
    if product_id is not None:
        where_clauses.append("product_id=?")
        params.append(product_id)
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.patch("/v1/products/update")
async def v1_products_update(
    productnumber: Optional[str] = None,
    product_name: Optional[str] = None,
    product_description: Optional[str] = None,
    product_type: Optional[int] = None,
    product_image_url: Optional[str] = None,
    document_id_ref: Optional[int] = None,
):
    """Update a product or create it if missing."""
    if not productnumber:
        raise HTTPException(status_code=400, detail="Missing parameter: needs productnumber")
    updates = []
    params: list = []
    if product_name is not None:
        updates.append("product_name=?")
        params.append(product_name)
    if product_description is not None:
        updates.append("product_description=?")
        params.append(product_description)
    if product_type is not None:
        updates.append("product_type=?")
        params.append(product_type)
    if product_image_url is not None:
        updates.append("product_image_url=?")
        params.append(product_image_url)
    if document_id_ref is not None:
        updates.append("document_id_ref=?")
        params.append(document_id_ref)
    if not updates:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs at least one of product_name, product_description, product_type, product_image_url, document_id_ref",
        )
    params.append(productnumber)
    rowcount = await db.execute(
        f"UPDATE products SET {', '.join(updates)} WHERE productnumber=?",
        tuple(params),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO products (productnumber, product_name, product_description, product_type, product_image_url, document_id_ref) VALUES (?, ?, ?, ?, ?, ?)",
            (
                productnumber,
                product_name or "",
                product_description or "",
                product_type or 1,
                product_image_url or "",
                document_id_ref,
            ),
        )
    return {"result": "OK"}


@app.get("/v1/products/type/list")
async def v1_products_type_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    product_type_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List product types."""
    query = "SELECT product_type_id, product_type_name, product_type_description FROM products_type"
    params: list = []
    if product_type_id is not None:
        query += " WHERE product_type_id=?"
        params.append(product_type_id)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/products/type/add")
async def v1_products_type_add(
    product_type_name: Optional[str] = None,
    product_type_description: Optional[str] = None,
):
    """Create a product type."""
    if not product_type_name:
        raise HTTPException(status_code=400, detail="Missing parameter: needs product_type_name")
    await db.execute(
        "INSERT INTO products_type (product_type_name, product_type_description) VALUES (?, ?)",
        (product_type_name, product_type_description or ""),
    )
    return {"result": "OK"}


@app.patch("/v1/products/type/update")
async def v1_products_type_update(
    product_type_id: Optional[int] = None,
    product_type_name: Optional[str] = None,
    product_type_description: Optional[str] = None,
):
    """Update or create a product type."""
    if product_type_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs product_type_id")
    updates = []
    params: list = []
    if product_type_name is not None:
        updates.append("product_type_name=?")
        params.append(product_type_name)
    if product_type_description is not None:
        updates.append("product_type_description=?")
        params.append(product_type_description)
    if not updates:
        raise HTTPException(status_code=400, detail="Missing parameter: needs product_type_name or product_type_description")
    params.append(product_type_id)
    rowcount = await db.execute(
        f"UPDATE products_type SET {', '.join(updates)} WHERE product_type_id=?",
        tuple(params),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO products_type (product_type_name, product_type_description) VALUES (?, ?)",
            (product_type_name or "", product_type_description or ""),
        )
    return {"result": "OK"}


@app.delete("/v1/products/type/delete")
async def v1_products_type_delete(product_type_id: Optional[int] = None):
    """Delete a product type."""
    if product_type_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs product_type_id")
    rowcount = await db.execute(
        "DELETE FROM products_type WHERE product_type_id=?",
        (product_type_id,),
    )
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No record for product_type_id:{product_type_id}")
    return {"message": "OK"}


@app.get("/v1/products/sensorunits/list")
async def v1_products_sensorunits_list(productnumber: Optional[str] = None):
    """List sensorunits associated with a product number."""
    query = "SELECT serialnumber FROM sensorunits"
    params: list = []
    if productnumber:
        query += " WHERE serialnumber LIKE ?"
        params.append(f"{productnumber}%")
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.get("/v1/sensorprobes/list")
async def v1_sensorprobes_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    productnumber: Optional[str] = None,
    unittype: Optional[int] = None,
    product_id_ref: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List sensor probes."""
    query = (
        "SELECT products.productnumber, product_id_ref, sensorprobes.hidden, sensorprobes_number, sensorprobes_alert_hidden, "
        "unittypes.unittype_id, unittypes.unittype_description, unittypes.unittype_shortlabel, unittypes.unittype_label, unittypes.unittype_decimals "
        "FROM sensorprobes INNER JOIN unittypes ON sensorprobes.unittype_id_ref = unittypes.unittype_id "
        "INNER JOIN products ON product_id_ref = product_id"
    )
    clauses = []
    params: list = []
    if productnumber:
        clauses.append("products.productnumber=?")
        params.append(productnumber)
    if unittype is not None:
        clauses.append("unittypes.unittype_id=?")
        params.append(unittype)
    if product_id_ref is not None:
        clauses.append("sensorprobes.product_id_ref=?")
        params.append(product_id_ref)
    if clauses:
        query += " WHERE " + " AND ".join(clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.patch("/v1/sensorprobes/update")
async def v1_sensorprobes_update(
    product_id_ref: Optional[int] = None,
    sensorprobes_number: Optional[int] = None,
    unittype_id_ref: Optional[int] = None,
    sensorprobes_url: Optional[str] = None,
    sensorprobes_alert_hidden: Optional[str] = None,
):
    """Update a sensor probe or create it if missing."""
    if product_id_ref is None or sensorprobes_number is None or unittype_id_ref is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs product_id_ref, sensorprobes_number and unittype_id_ref",
        )
    updates = ["unittype_id_ref=?"]
    params: list = [unittype_id_ref]
    if sensorprobes_url is not None:
        updates.append("sensorprobes_url=?")
        params.append(sensorprobes_url)
    if sensorprobes_alert_hidden is not None:
        updates.append("sensorprobes_alert_hidden=?")
        params.append(sensorprobes_alert_hidden)
    params.extend([product_id_ref, sensorprobes_number])
    rowcount = await db.execute(
        f"UPDATE sensorprobes SET {', '.join(updates)} WHERE product_id_ref=? AND sensorprobes_number=?",
        tuple(params),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO sensorprobes (product_id_ref, sensorprobes_number, unittype_id_ref, sensorprobes_url, sensorprobes_alert_hidden) VALUES (?, ?, ?, ?, ?)",
            (product_id_ref, sensorprobes_number, unittype_id_ref, sensorprobes_url or "", sensorprobes_alert_hidden or ""),
        )
    return {"result": "OK"}


@app.delete("/v1/sensorprobes/delete")
async def v1_sensorprobes_delete(
    product_id_ref: Optional[int] = None,
    sensorprobes_number: Optional[int] = None,
):
    """Delete a sensor probe."""
    if product_id_ref is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs product_id_ref")
    where = "product_id_ref=?"
    params: list = [product_id_ref]
    if sensorprobes_number is not None:
        where += " AND sensorprobes_number=?"
        params.append(sensorprobes_number)
    rowcount = await db.execute(
        f"DELETE FROM sensorprobes WHERE {where}",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No record for product_id_ref:{product_id_ref}, sensorprobes_number:{sensorprobes_number}",
        )
    return {"message": "OK"}


@app.get("/v1/sensorprobes/variable/list")
async def v1_sensorprobes_variable_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    serialnumber: Optional[str] = None,
    sensorprobe_number: Optional[int] = None,
    variable: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List sensor probe variables."""
    query = "SELECT serialnumber, sensorprobe_number, variable, value, dateupdated FROM sensorprobe_variables"
    clauses = []
    params: list = []
    if serialnumber:
        clauses.append("serialnumber=?")
        params.append(serialnumber)
    if sensorprobe_number is not None:
        clauses.append("sensorprobe_number=?")
        params.append(sensorprobe_number)
    if variable is not None:
        clauses.append("variable=?")
        params.append(variable)
    if clauses:
        query += " WHERE " + " AND ".join(clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.patch("/v1/sensorprobes/variable/update")
async def v1_sensorprobes_variable_update(
    serialnumber: Optional[str] = None,
    sensorprobe_number: Optional[int] = None,
    variable: Optional[str] = None,
    value: Optional[str] = None,
):
    """Update or create a sensor probe variable."""
    if not serialnumber or sensorprobe_number is None or not variable or value is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs serialnumber, sensorprobe_number, variable and value",
        )
    rowcount = await db.execute(
        "UPDATE sensorprobe_variables SET value=?, dateupdated=CURRENT_TIMESTAMP WHERE serialnumber=? AND sensorprobe_number=? AND variable=?",
        (value, serialnumber, sensorprobe_number, variable),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO sensorprobe_variables (serialnumber, sensorprobe_number, variable, value, dateupdated) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)",
            (serialnumber, sensorprobe_number, variable, value),
        )
    return {"result": "OK"}


@app.delete("/v1/sensorprobes/variable/delete")
async def v1_sensorprobes_variable_delete(
    serialnumber: Optional[str] = None,
    sensorprobe_number: Optional[int] = None,
    variable: Optional[str] = None,
):
    """Delete a sensor probe variable."""
    if not serialnumber or sensorprobe_number is None or not variable:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs serialnumber, sensorprobe_number and variable",
        )
    rowcount = await db.execute(
        "DELETE FROM sensorprobe_variables WHERE serialnumber=? AND sensorprobe_number=? AND variable=?",
        (serialnumber, sensorprobe_number, variable),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No record for serialnumber:{serialnumber}, sensorprobe_number:{sensorprobe_number} variable:{variable}",
        )
    return {"message": "OK"}


@app.post("/v1/sensorunits/access/grant")
async def v1_sensorunits_access_grant(
    user_id: Optional[int] = None,
    serialnumber: Optional[str] = None,
    user_email: Optional[str] = None,
    changeallowed: Optional[str] = None,
):
    """Grant access to a sensorunit for a user."""
    if user_id is None or not serialnumber or not user_email or changeallowed is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs user_id, serialnumber, user_email and changeallowed",
        )
    row = await db.fetchone("SELECT user_id FROM users WHERE user_email=?", (user_email,))
    if row is None:
        raise HTTPException(status_code=400, detail=f"User with email:{user_email} is not found")
    uid = row["user_id"]
    await db.execute("DELETE FROM sensoraccess WHERE user_id=? AND serialnumber=?", (uid, serialnumber))
    await db.execute(
        "INSERT INTO sensoraccess (user_id, serialnumber, changeallowed) VALUES (?, ?, ?)",
        (uid, serialnumber, changeallowed),
    )
    return {"message": "OK"}


@app.delete("/v1/sensorunits/access/delete")
async def v1_sensorunits_access_delete(
    serialnumber: Optional[str] = None,
    user_id: Optional[int] = None,
    user_email: Optional[str] = None,
):
    """Remove a user's access to a sensorunit."""
    if not serialnumber or user_id is None or not user_email:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs serialnumber,user_id and user_email",
        )
    row = await db.fetchone("SELECT user_id FROM users WHERE user_email=?", (user_email,))
    if row is None:
        raise HTTPException(status_code=400, detail=f"User with email:{user_email} is not found")
    uid = row["user_id"]
    rowcount = await db.execute(
        "DELETE FROM sensoraccess WHERE user_id=? AND serialnumber=?",
        (uid, serialnumber),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No record for user_email:{user_email} and serialnumber={serialnumber}.",
        )
    return {"message": "OK"}


@app.get("/v1/sensorunits/access/list")
async def v1_sensorunits_access_list(
    serialnumber: Optional[str] = None,
    user_id: Optional[int] = None,
):
    """List sensorunit access records."""
    if not serialnumber and user_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber user_id")
    if serialnumber:
        rows = await db.fetchall(
            "SELECT serialnumber,user_id,changeallowed FROM sensoraccess WHERE serialnumber=?",
            (serialnumber,),
        )
    else:
        rows = await db.fetchall(
            "SELECT serialnumber,user_id,changeallowed FROM sensoraccess WHERE user_id=?",
            (user_id,),
        )
    return {"result": rows}


@app.post("/v1/sensorunits/add")
async def v1_sensorunits_add(
    serialnumber: Optional[str] = None,
    dbname: Optional[str] = None,
    product_id_ref: Optional[int] = None,
    customer_id_ref: Optional[int] = None,
    helpdesk_id_ref: Optional[int] = None,
    sensorunit_installdate: Optional[str] = "1970-01-01",
    sensorunit_lastconnect: Optional[str] = "1970-01-01",
    sensorunit_location: Optional[str] = "",
    sensorunit_note: Optional[str] = "",
    sensorunit_position: Optional[str] = "",
    sensorunit_status: Optional[int] = 0,
):
    """Insert a new sensorunit."""
    if (
        not serialnumber
        or not dbname
        or product_id_ref is None
        or customer_id_ref is None
        or helpdesk_id_ref is None
    ):
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs at least serialnumber, dbname, product_id_ref, customer_id_ref, helpdesk_id_ref",
        )
    existing = await db.fetchone(
        "SELECT serialnumber FROM sensorunits WHERE serialnumber=?",
        (serialnumber,),
    )
    if existing:
        raise HTTPException(status_code=302, detail=f"Record exists for serialnumber:{serialnumber}")
    await db.execute(
        """
        INSERT INTO sensorunits (
            serialnumber, dbname, product_id_ref, customer_id_ref, helpdesk_id_ref,
            sensorunit_installdate, sensorunit_lastconnect, sensorunit_location,
            sensorunit_note, sensorunit_position, sensorunit_status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            serialnumber,
            dbname,
            product_id_ref,
            customer_id_ref,
            helpdesk_id_ref,
            sensorunit_installdate,
            sensorunit_lastconnect,
            sensorunit_location,
            sensorunit_note,
            sensorunit_position,
            sensorunit_status,
        ),
    )
    return {"result": "OK"}


@app.patch("/v1/sensorunits/update")
async def v1_sensorunits_update(
    serialnumber: Optional[str] = None,
    dbname: Optional[str] = None,
    product_id_ref: Optional[int] = None,
    customer_id_ref: Optional[int] = None,
    helpdesk_id_ref: Optional[int] = None,
    sensorunit_installdate: Optional[str] = None,
    sensorunit_lastconnect: Optional[str] = None,
    sensorunit_location: Optional[str] = None,
    sensorunit_note: Optional[str] = None,
    sensorunit_position: Optional[str] = None,
    sensorunit_status: Optional[int] = None,
    block: Optional[int] = None,
):
    """Update an existing sensorunit."""
    if not serialnumber:
        raise HTTPException(status_code=400, detail="Missing parameter: needs at least serialnumber")
    updates = []
    params: list = []
    for column, value in [
        ("dbname", dbname),
        ("product_id_ref", product_id_ref),
        ("customer_id_ref", customer_id_ref),
        ("helpdesk_id_ref", helpdesk_id_ref),
        ("sensorunit_installdate", sensorunit_installdate),
        ("sensorunit_lastconnect", sensorunit_lastconnect),
        ("sensorunit_location", sensorunit_location),
        ("sensorunit_note", sensorunit_note),
        ("sensorunit_position", sensorunit_position),
        ("sensorunit_status", sensorunit_status),
        ("block", block),
    ]:
        if value is not None:
            updates.append(f"{column}=?")
            params.append(value)
    if not updates:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs at least one: dbname, product_id_ref, customer_id_ref, helpdesk_id_ref, sensorunit_installdate,sensorunit_lastconnect,sensorunit_location,sensorunit_note,sensorunit_position,sensorunit_status",
        )
    params.append(serialnumber)
    rowcount = await db.execute(
        f"UPDATE sensorunits SET {', '.join(updates)} WHERE serialnumber=?",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"Missing record for serialnumber:{serialnumber}",
        )
    return {"result": "OK"}


@app.delete("/v1/sensorunits/delete")
async def v1_sensorunits_delete(
    serialnumber: Optional[str] = None,
    sensorunit_id: Optional[int] = None,
):
    """Delete a sensorunit."""
    if not serialnumber and sensorunit_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber or senorsunit_id")
    if sensorunit_id is not None:
        where = "sensorunit_id=?"
        param = sensorunit_id
    else:
        where = "serialnumber=?"
        param = serialnumber
    rowcount = await db.execute(f"DELETE FROM sensorunits WHERE {where}", (param,))
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No record for for serialnumber:{serialnumber} or sensorunit_id:{sensorunit_id}.",
        )
    return {"message": "OK"}


@app.get("/v1/sensorunits/list")
async def v1_sensorunits_list(
    user_id: Optional[int] = None,
    serialnumber: Optional[str] = None,
    productnumber: Optional[str] = None,
    sortfield: Optional[str] = None,
):
    """List sensorunits for a user."""
    query = (
        "SELECT sensoraccess.serialnumber, sensoraccess.changeallowed, sensoraccess.user_id, "
        "products.product_name, products.productnumber, sensorunits.sensorunit_installdate, "
        "sensorunits.sensorunit_lastconnect, sensorunits.sensorunit_location, sensorunits.sensorunit_status, "
        "customer.customernumber, customer.customer_name "
        "FROM sensoraccess "
        "INNER JOIN sensorunits ON (sensoraccess.serialnumber = sensorunits.serialnumber) "
        "INNER JOIN products ON (sensorunits.product_id_ref = products.product_id) "
        "INNER JOIN customer ON (sensorunits.customer_id_ref = customer.customer_id)"
    )
    clauses = []
    params: list = []
    if user_id is not None:
        clauses.append("sensoraccess.user_id=?")
        params.append(user_id)
    if serialnumber:
        clauses.append("sensoraccess.serialnumber=?")
        params.append(serialnumber)
    if productnumber:
        clauses.append("substr(sensoraccess.serialnumber,1,10)=?")
        params.append(productnumber)
    if clauses:
        query += " WHERE " + " AND ".join(clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.get("/v1/sensorunits/units/list")
async def v1_sensorunits_units_list(
    user_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List unit types for sensorunits a user has access to."""
    query = (
        "SELECT DISTINCT unittypes.unittype_description FROM sensoraccess "
        "INNER JOIN products ON substr(sensoraccess.serialnumber,1,10)=substr(products.productnumber,1,10) "
        "INNER JOIN sensorprobes ON sensorprobes.product_id_ref=products.product_id "
        "INNER JOIN unittypes ON sensorprobes.sensorprobes_number = unittypes.unittype_id"
    )
    params: list = []
    if user_id is not None:
        query += " WHERE sensoraccess.user_id=?"
        params.append(user_id)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.get("/v1/sensorunits/all")
async def v1_sensorunits_all(
    serialnumber: Optional[str] = None,
    sensorunit_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List all sensorunits joined with related info."""
    query = (
        "SELECT sensorunits.serialnumber, sensorunits.dbname, sensorunits.sensorunit_installdate, "
        "sensorunits.sensorunit_lastconnect, sensorunits.sensorunit_location, sensorunits.sensorunit_note, "
        "sensorunits.sensorunit_status, sensorunits.product_id_ref, sensorunits.customer_id_ref, "
        "sensorunits.helpdesk_id_ref, sensorunits.sensorunit_position, sensorunits.block, "
        "products.product_name, customer.customer_name, helpdesks.helpdesk_name, sensorunits.sensorunit_id "
        "FROM sensorunits "
        "INNER JOIN products ON sensorunits.product_id_ref = products.product_id "
        "INNER JOIN customer ON sensorunits.customer_id_ref = customer.customer_id "
        "INNER JOIN helpdesks ON sensorunits.helpdesk_id_ref = helpdesks.helpdesk_id"
    )
    clauses = []
    params: list = []
    if serialnumber:
        clauses.append("sensorunits.serialnumber=?")
        params.append(serialnumber)
    if sensorunit_id is not None:
        clauses.append("sensorunits.sensorunit_id=?")
        params.append(sensorunit_id)
    if clauses:
        query += " WHERE " + " AND ".join(clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/sensorunits/variable/add")
async def v1_sensorunits_variable_add(
    serialnumber: Optional[str] = None,
    variable: Optional[str] = None,
    value: Optional[str] = "0",
):
    """Create a sensorunit variable."""
    if not serialnumber or variable is None:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs serialnumber and variable",
        )
    existing = await db.fetchone(
        "SELECT serialnumber FROM sensorunit_variables WHERE serialnumber=? AND variable=?",
        (serialnumber, variable),
    )
    if existing:
        raise HTTPException(
            status_code=302,
            detail=f"Record exists for serialnumber:{serialnumber} and variable:{variable}",
        )
    await db.execute(
        "INSERT INTO sensorunit_variables (serialnumber, variable, value) VALUES (?, ?, ?)",
        (serialnumber, variable, value or "0"),
    )
    return {"result": "OK"}


@app.patch("/v1/sensorunits/variable/update")
async def v1_sensorunits_variable_update(
    serialnumber: Optional[str] = None,
    variable: Optional[str] = None,
    value: Optional[str] = None,
):
    """Update or create a sensorunit variable."""
    if not serialnumber or not variable:
        raise HTTPException(
            status_code=400,
            detail="Missing parameter: needs serialnumber and variable",
        )
    rowcount = await db.execute(
        "UPDATE sensorunit_variables SET value=? WHERE serialnumber=? AND variable=?",
        (value or "0", serialnumber, variable),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO sensorunit_variables (serialnumber, variable, value) VALUES (?, ?, ?)",
            (serialnumber, variable, value or "0"),
        )
    return {"result": "OK"}


@app.delete("/v1/sensorunits/variable/delete")
async def v1_sensorunits_variable_delete(
    serialnumber: Optional[str] = None,
    variable: Optional[str] = None,
):
    """Delete a sensorunit variable."""
    if not serialnumber:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber")
    where = "serialnumber=?"
    params: list = [serialnumber]
    if variable is not None:
        where += " AND variable=?"
        params.append(variable)
    rowcount = await db.execute(
        f"DELETE FROM sensorunit_variables WHERE {where}",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No record for serialnumber:{serialnumber}.",
        )
    return {"result": "OK"}


@app.get("/v1/sensorunits/variable/get")
async def v1_sensorunits_variable_get(
    serialnumber: Optional[str] = None,
    productnumber: Optional[str] = None,
    variable: Optional[str] = None,
):
    """List sensorunit variables."""
    try:
        if not serialnumber and not productnumber:
            raise HTTPException(
                status_code=400,
                detail="Missing parameter: needs serialnumber or productnumber",
            )
        query = (
            "SELECT serialnumber, variable, value, dateupdated FROM sensorunit_variables"
        )
        clauses = []
        params: list = []
        if serialnumber:
            clauses.append("serialnumber=?")
            params.append(serialnumber)
        if productnumber:
            clauses.append("serialnumber LIKE ?")
            params.append(f"{productnumber}%")
        if variable:
            clauses.append("variable=?")
            params.append(variable)
        if clauses:
            query += " WHERE " + " AND ".join(clauses)
        rows = await db.fetchall(query, tuple(params))
        return {"result": rows}
    except Exception:
        logging.exception("Feil i /v1/sensorunits/variable/get")
        raise


@app.get("/v1/unittypes/list")
async def v1_unittypes_list(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    unittype_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List unit types."""
    query = "SELECT unittype_id, unittype_description, unittype_shortlabel, unittype_label, unittype_decimals FROM unittypes"
    params: list = []
    if unittype_id is not None:
        query += " WHERE unittype_id=?"
        params.append(unittype_id)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.patch("/v1/unittypes/update")
async def v1_unittypes_update(
    unittype_id: Optional[int] = None,
    unittype_description: Optional[str] = None,
    unittype_shortlabel: Optional[str] = None,
    unittype_label: Optional[str] = None,
    unittype_decimals: Optional[int] = None,
):
    """Update or create a unit type."""
    if unittype_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs unittype_id")
    updates = []
    params: list = []
    if unittype_description is not None:
        updates.append("unittype_description=?")
        params.append(unittype_description)
    if unittype_shortlabel is not None:
        updates.append("unittype_shortlabel=?")
        params.append(unittype_shortlabel)
    if unittype_label is not None:
        updates.append("unittype_label=?")
        params.append(unittype_label)
    if unittype_decimals is not None:
        updates.append("unittype_decimals=?")
        params.append(unittype_decimals)
    if not updates:
        raise HTTPException(status_code=400, detail="Missing parameter: needs at least one field to update")
    params.append(unittype_id)
    rowcount = await db.execute(
        f"UPDATE unittypes SET {', '.join(updates)} WHERE unittype_id=?",
        tuple(params),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO unittypes (unittype_id, unittype_description, unittype_shortlabel, unittype_label, unittype_decimals) VALUES (?, ?, ?, ?, ?)",
            (
                unittype_id,
                unittype_description or "",
                unittype_shortlabel or "",
                unittype_label or "",
                unittype_decimals or 0,
            ),
        )
    return {"result": "OK"}


@app.delete("/v1/unittypes/delete")
async def v1_unittypes_delete(unittype_id: Optional[int] = None):
    """Delete a unit type."""
    if unittype_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs unittype_id")
    rowcount = await db.execute(
        "DELETE FROM unittypes WHERE unittype_id=?",
        (unittype_id,),
    )
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No record for unittype_id:{unittype_id}")
    return {"message": "OK"}


@app.get("/v1/sensorunits/data")
async def v1_sensorunits_data(
    serialnumber: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    probenumber: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List sensordata entries for a sensor unit."""
    if not serialnumber:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber")
    query = (
        "SELECT probenumber, sequencenumber, value, timestamp "
        "FROM sensordata WHERE serialnumber=?"
    )
    params: list = [serialnumber]
    if probenumber is not None:
        query += " AND probenumber=?"
        params.append(probenumber)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.get("/v1/sensorunits/data/latest")
async def v1_sensorunits_data_latest(
    serialnumber: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    probenumber: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List latest sensor readings for a sensor unit."""
    if not serialnumber:
        raise HTTPException(status_code=400, detail="Missing parameter: needs serialnumber")
    query = (
        "SELECT probenumber, value, timestamp "
        "FROM sensorslatestvalues WHERE serialnumber=?"
    )
    params: list = [serialnumber]
    if probenumber is not None:
        query += " AND probenumber=?"
        params.append(probenumber)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
    if offset is not None:
        query += " OFFSET ?"
        params.append(offset)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/user/add")
async def v1_user_add(
    user_email: Optional[str] = None,
    user_password: Optional[str] = "",
    user_name: Optional[str] = "",
    customer_id_ref: Optional[int] = None,
):
    """Create a user."""
    if not user_email:
        raise HTTPException(status_code=400, detail="Missing parameter: needs user_email")
    existing = await db.fetchone("SELECT user_id FROM users WHERE user_email=?", (user_email,))
    if existing:
        raise HTTPException(status_code=302, detail="Users email already exists")
    await db.execute(
        "INSERT INTO users (customer_id_ref, user_email, user_password, user_name) VALUES (?, ?, ?, ?)",
        (customer_id_ref, user_email, user_password or "", user_name or ""),
    )
    return {"result": "OK"}


@app.patch("/v1/user/update")
async def v1_user_update(
    user_id: Optional[int] = None,
    user_email: Optional[str] = None,
    user_name: Optional[str] = None,
    user_phone_work: Optional[str] = None,
    user_password: Optional[str] = None,
    user_roletype_id: Optional[int] = None,
    user_language: Optional[str] = None,
):
    """Update user details."""
    if user_id is None and not user_email:
        raise HTTPException(status_code=400, detail="Missing parameter: needs user_id or user_email")
    updates: list[str] = []
    params: list = []
    for column, value in [
        ("user_name", user_name),
        ("user_phone_work", user_phone_work),
        ("user_password", user_password),
        ("user_roletype_id", user_roletype_id),
        ("user_language", user_language),
    ]:
        if value is not None:
            updates.append(f"{column}=?")
            params.append(value)
    if user_id is not None and user_email is not None:
        updates.append("user_email=?")
        params.append(user_email)
    if not updates:
        raise HTTPException(status_code=400, detail="Missing parameter: needs at least one field to update")
    if user_id is not None:
        params.append(user_id)
        where = "user_id=?"
    else:
        params.append(user_email)
        where = "user_email=?"
    rowcount = await db.execute(
        f"UPDATE users SET {', '.join(updates)} WHERE {where}",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(status_code=404, detail="No record found")
    return {"result": "OK"}


@app.delete("/v1/user/delete")
async def v1_user_delete(user_id: Optional[int] = None):
    """Delete a user."""
    if user_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs user_id")
    rowcount = await db.execute("DELETE FROM users WHERE user_id=?", (user_id,))
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No userid for id:{user_id}")
    return {"message": "OK"}


@app.get("/v1/user/list")
async def v1_user_list(
    limit: Optional[int] = None,
    page: Optional[int] = None,
    user_email: Optional[str] = None,
    user_id: Optional[int] = None,
    sortfield: Optional[str] = None,
):
    """List users."""
    query = (
        "SELECT user_id,user_name,user_phone_work,user_email,user_password,user_language,user_roletype_id "
        "FROM users"
    )
    clauses: list[str] = []
    params: list = []
    if user_email:
        clauses.append("user_email=?")
        params.append(user_email)
    if user_id is not None:
        clauses.append("user_id=?")
        params.append(user_id)
    if clauses:
        query += " WHERE " + " AND ".join(clauses)
    if sortfield:
        query += f" ORDER BY {sortfield}"
    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
        if page is not None:
            query += " OFFSET ?"
            params.append(max(page - 1, 0) * limit)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}


@app.post("/v1/user/variable/add")
async def v1_user_variable_add(
    user_id: Optional[int] = None,
    variable: Optional[str] = None,
    value: Optional[str] = "0",
):
    """Create a user variable."""
    if user_id is None or variable is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs user_id and variable")
    existing = await db.fetchone(
        "SELECT user_id FROM user_variables WHERE user_id=? AND variable=?",
        (user_id, variable),
    )
    if existing:
        raise HTTPException(
            status_code=302,
            detail=f"Record exists for user_id:{user_id} and variable:{variable}",
        )
    await db.execute(
        "INSERT INTO user_variables (user_id, variable, value) VALUES (?, ?, ?)",
        (user_id, variable, value or "0"),
    )
    return {"result": "OK"}


@app.patch("/v1/user/variable/update")
async def v1_user_variable_update(
    user_id: Optional[int] = None,
    variable: Optional[str] = None,
    value: Optional[str] = None,
):
    """Update or create a user variable."""
    if user_id is None or variable is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs user_id and variable")
    rowcount = await db.execute(
        "UPDATE user_variables SET value=? WHERE user_id=? AND variable=?",
        (value or "0", user_id, variable),
    )
    if rowcount == 0:
        await db.execute(
            "INSERT INTO user_variables (user_id, variable, value) VALUES (?, ?, ?)",
            (user_id, variable, value or "0"),
        )
    return {"result": "OK"}


@app.delete("/v1/user/variable/delete")
async def v1_user_variable_delete(
    user_id: Optional[int] = None,
    variable: Optional[str] = None,
    user_variables_id: Optional[int] = None,
):
    """Delete a user variable."""
    if user_id is None:
        raise HTTPException(status_code=400, detail="Missing parameter: needs user_id")
    where = ["user_id=?"]
    params: list = [user_id]
    if variable is not None:
        where.append("variable=?")
        params.append(variable)
    if user_variables_id is not None:
        where.append("user_variables_id=?")
        params.append(user_variables_id)
    rowcount = await db.execute(
        f"DELETE FROM user_variables WHERE {' AND '.join(where)}",
        tuple(params),
    )
    if rowcount == 0:
        raise HTTPException(status_code=404, detail=f"No record for user_id:{user_id}")
    return {"result": "OK"}


@app.get("/v1/user/variable/get")
async def v1_user_variable_get(
    user_id: Optional[int] = None,
    variable: Optional[str] = None,
):
    """List user variables."""
    query = "SELECT user_variables_id, user_id, variable, value, updated_at, created_at FROM user_variables"
    clauses = []
    params: list = []
    if user_id is not None:
        clauses.append("user_id=?")
        params.append(user_id)
    if variable is not None:
        clauses.append("variable=?")
        params.append(variable)
    if clauses:
        query += " WHERE " + " AND ".join(clauses)
    rows = await db.fetchall(query, tuple(params))
    return {"result": rows}

