# PortalWeb API Porting Progress

The following table lists all FastAPI endpoints ported from the original Perl
implementation. Each endpoint is marked ✅ if it has a matching counterpart in
`portalwebapi.pl`.

| Method | Endpoint | Status |
| ------ | -------- | ------ |
| GET | /v1/countries/list | ✅ |
| POST | /v1/customers/add | ✅ |
| DELETE | /v1/customers/delete | ✅ |
| GET | /v1/customers/list | ✅ |
| PATCH | /v1/customers/update | ✅ |
| DELETE | /v1/customers/variable/delete | ✅ |
| GET | /v1/customers/variable/list | ✅ |
| PATCH | /v1/customers/variable/update | ✅ |
| POST | /v1/customertypes/add | ✅ |
| DELETE | /v1/customertypes/delete | ✅ |
| GET | /v1/customertypes/list | ✅ |
| PATCH | /v1/customertypes/update | ✅ |
| POST | /v1/document/add | ✅ |
| DELETE | /v1/document/delete | ✅ |
| GET | /v1/document/list | ✅ |
| POST | /v1/event/add | ✅ |
| POST | /v1/gui/viewgroup/add | ✅ |
| DELETE | /v1/gui/viewgroup/delete | ✅ |
| GET | /v1/gui/viewgroup/list | ✅ |
| POST | /v1/gui/viewgroup/order/add | ✅ |
| DELETE | /v1/gui/viewgroup/order/delete | ✅ |
| GET | /v1/gui/viewgroup/order/list | ✅ |
| PATCH | /v1/gui/viewgroup/order/update | ✅ |
| PATCH | /v1/gui/viewgroup/update | ✅ |
| POST | /v1/helpdesks/add | ✅ |
| DELETE | /v1/helpdesks/delete | ✅ |
| GET | /v1/helpdesks/list | ✅ |
| PATCH | /v1/helpdesks/update | ✅ |
| GET | /v1/irrigation/runlog/list | ✅ |
| PATCH | /v1/irrigation/runlog/update | ✅ |
| POST | /v1/messages/add | ✅ |
| DELETE | /v1/messages/delete | ✅ |
| GET | /v1/messages/list | ✅ |
| PATCH | /v1/messages/update | ✅ |
| DELETE | /v1/products/delete | ✅ |
| GET | /v1/products/list | ✅ |
| GET | /v1/products/sensorunits/list | ✅ |
| POST | /v1/products/type/add | ✅ |
| DELETE | /v1/products/type/delete | ✅ |
| GET | /v1/products/type/list | ✅ |
| PATCH | /v1/products/type/update | ✅ |
| PATCH | /v1/products/update | ✅ |
| POST | /v1/pushmessage | ✅ |
| POST | /v1/sendmessage | ✅ |
| POST | /v1/sendsms | ✅ |
| POST | /v1/sensordata/add | ✅ |
| PATCH | /v1/sensordata/rename | ✅ |
| DELETE | /v1/sensorprobes/delete | ✅ |
| GET | /v1/sensorprobes/list | ✅ |
| PATCH | /v1/sensorprobes/update | ✅ |
| DELETE | /v1/sensorprobes/variable/delete | ✅ |
| GET | /v1/sensorprobes/variable/list | ✅ |
| PATCH | /v1/sensorprobes/variable/update | ✅ |
| PATCH | /v1/sensorunit/move2customer | ✅ |
| PATCH | /v1/sensorunit/ports/output/off | ✅ |
| PATCH | /v1/sensorunit/ports/output/on | ✅ |
| GET | /v1/sensorunit/ports/output/status | ✅ |
| DELETE | /v1/sensorunits/access/delete | ✅ |
| POST | /v1/sensorunits/access/grant | ✅ |
| GET | /v1/sensorunits/access/list | ✅ |
| POST | /v1/sensorunits/add | ✅ |
| GET | /v1/sensorunits/all | ✅ |
| GET | /v1/sensorunits/data | ✅ |
| GET | /v1/sensorunits/data/latest | ✅ |
| DELETE | /v1/sensorunits/delete | ✅ |
| GET | /v1/sensorunits/list | ✅ |
| GET | /v1/sensorunits/units/list | ✅ |
| PATCH | /v1/sensorunits/update | ✅ |
| POST | /v1/sensorunits/variable/add | ✅ |
| DELETE | /v1/sensorunits/variable/delete | ✅ |
| GET | /v1/sensorunits/variable/get | ✅ |
| PATCH | /v1/sensorunits/variable/update | ✅ |
| DELETE | /v1/unittypes/delete | ✅ |
| GET | /v1/unittypes/list | ✅ |
| PATCH | /v1/unittypes/update | ✅ |
| POST | /v1/user/add | ✅ |
| DELETE | /v1/user/delete | ✅ |
| GET | /v1/user/list | ✅ |
| PATCH | /v1/user/update | ✅ |
| POST | /v1/user/variable/add | ✅ |
| DELETE | /v1/user/variable/delete | ✅ |
| GET | /v1/user/variable/get | ✅ |
| PATCH | /v1/user/variable/update | ✅ |
| GET | /v1/variabletypes/list | ✅ |


## Notes
- Queries now support asyncpg via automatic placeholder conversion from `?` to `$n` in `portal_db.py`.

- The API now opens the database connection pool on FastAPI startup and closes it on shutdown.

