from rest_framework import serializers
from phonenumber_field.serializerfields import PhoneNumberField
from .models import Product, Order, OrderItem


class OrderItemSerializer(serializers.Serializer):
    product = serializers.IntegerField(min_value=1)
    quantity = serializers.IntegerField(min_value=1)


class OrderSerializer(serializers.Serializer):
    firstname = serializers.CharField(max_length=100)
    lastname = serializers.CharField(max_length=100)
    phonenumber = PhoneNumberField(region='RU')
    address = serializers.CharField(max_length=255)

    products = OrderItemSerializer(many=True, allow_empty=False)

    def create(self, validated_data):
        order_items_payload = validated_data.pop('products')
        order_instance = Order.objects.create(
            client_name=validated_data['firstname'],
            surname=validated_data['lastname'],
            phone=validated_data['phonenumber'],
            delivery_address=validated_data['address']
        )

        for item_payload in order_items_payload:
            product_id = item_payload['product']
            quantity_value = item_payload['quantity']

            try:
                product_object = Product.objects.get(id=product_id)
            except Product.DoesNotExist:
                raise serializers.ValidationError(
                    {'products': [f'Недопустимый первичный ключ "{product_id}".']}
                )

            OrderItem.objects.create(
                order=order_instance,
                product=product_object,
                quantity=quantity_value
            )

        return order_instance

