from rest_framework import serializers
from phonenumber_field.serializerfields import PhoneNumberField
from .models import Product, Order, OrderItem
from django.db import  transaction

class OrderItemSerializer(serializers.Serializer):
    product = serializers.IntegerField(min_value=1)
    quantity = serializers.IntegerField(min_value=1)



class OrderSerializer(serializers.Serializer):
    id = serializers.IntegerField(read_only=True)
    firstname = serializers.CharField(max_length=100, source='client_name')
    lastname = serializers.CharField(max_length=100, source='surname')
    phonenumber = PhoneNumberField(region='RU', source='phone')
    address = serializers.CharField(max_length=255, source='delivery_address')

    products = OrderItemSerializer(many=True, allow_empty=False, write_only=True)

    def create(self, validated_data):
        order_items_payload = validated_data.pop('products')
        with transaction.atomic():
            order_instance = Order.objects.create(
                client_name=validated_data['client_name'],
                surname=validated_data['surname'],
                phone=validated_data['phone'],
                delivery_address=validated_data['delivery_address']
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
                    quantity=quantity_value,
                    price_at_purchase=product_object.price
                )

        return order_instance

