'use strict';

console.log('Loading function');

var AWS = require('aws-sdk');
AWS.config.update({apiVersion: '2012-08-10'});

var dynamodb = new AWS.DynamoDB.DocumentClient();
let tableName = process.env.DYNAMODB_BOUNCE_TABLE_NAME;

exports.handler = (event, context, callback) => {
  event.Records.forEach((record) => {
    let message;

    try {
      const snsMessage = JSON.parse(record.body);
      if (snsMessage.Type === "Notification" && snsMessage.Message) {
        message = JSON.parse(snsMessage.Message);
      } else {
        message = JSON.parse(record.body);
      }
    } catch (error) {
      console.log("Error parsing message body:", error);
      return;
    }

    //console.log('Parsed message:', JSON.stringify(message, null, 2));

    if (!message.eventType) {
      console.log("No eventType found in message:", JSON.stringify(message, null, 2));
      return;
    }

    switch (message.eventType) {
      case "Bounce":
        handleBounce(message);
        break;
      case "Complaint":
        handleComplaint(message);
        break;
      case "DeliveryDelay":
        handleDeliveryDelay(message);
        break;
      case "Delivery":
        handleDelivery(message);
        break;
      default:
        console.log("Unknown notification type: " + message.eventType);
    }
  });
};


function handleBounce(message) {
  const messageId = message.mail.messageId;
  const addresses = message.bounce.bouncedRecipients.map(function(recipient) {
    return recipient.emailAddress;
  });
  const bounceType = message.bounce.bounceType;

  addresses.forEach((address) => {
    writeDDB(address, message, tableName, "disable");
  });
}

function handleComplaint(message) {
  const messageId = message.mail.messageId;
  const addresses = message.complaint.complainedRecipients.map(function(recipient) {
    return recipient.emailAddress;
  });

  addresses.forEach((address) => {
    writeDDB(address, message, tableName, "disable");
  });
}

function handleDeliveryDelay(message) {
  const messageId = message.mail.messageId;
  const addresses = message.deliveryDelay.delayedRecipients.map(function(recipient) {
    return recipient.emailAddress;
  });

  addresses.forEach((address) => {
    writeDDB(address, message, tableName, "disable");
  });
}

function handleDelivery(message) {
  const messageId = message.mail.messageId;
  const deliveryTimestamp = message.delivery.timestamp;
  const addresses = message.delivery.recipients;

  addresses.forEach((address) => {
    writeDDB(address, message, tableName, "enable");
  });
}

function writeDDB(id, payload, tableName, status) {
  const TTL_DELTA = 60 * 60 * 24 * 30;
  const domain = payload.mail.source.split('@')[1];

  dynamodb.put({
    TableName: tableName,
    Item: {
      UserId: id,
      eventType: payload.eventType,
      from: payload.mail.source,
      domain: domain,
      subject: payload.mail.commonHeaders.subject,
      Type: payload?.bounce?.bounceType || payload?.deliveryDelay?.delayType,
      SubType: payload?.bounce?.bounceSubType,
      Diag: payload?.bounce?.bouncedRecipients[0]?.diagnosticCode || payload?.deliveryDelay?.delayedRecipients[0]?.diagnosticCode,
      reason: payload?.bounce?.reason,
      messageId: payload.mail.messageId,
      date: payload.mail.timestamp,
      state: status,
      ttl: Math.floor(Date.now() / 1000) + TTL_DELTA
    }
  }, function(err, data) {
    if (err) {
      console.log(`Error putting item into DynamoDB failed: ${JSON.stringify(err)}`);
    } else {
      console.log('Put item success: ' + JSON.stringify(data, null, '  '));
    }
  });
}
